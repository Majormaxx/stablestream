// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IYieldSource} from "../interfaces/IYieldSource.sol";

// ---------------------------------------------------------------------------
// Minimal Compound V3 (Comet) interface — only the functions we need
// ---------------------------------------------------------------------------

/// @dev Compound V3 Comet contract.  On Unichain this is the USDC market.
interface IComet {
    /// @notice Supply `amount` of `asset` to the Comet market.
    ///         The caller's balance in Comet increases by `amount`.
    function supply(address asset, uint256 amount) external;

    /// @notice Withdraw `amount` of `asset` from the caller's Comet balance.
    function withdraw(address asset, uint256 amount) external;

    /// @notice Returns the raw balance of `account` inside Comet (principal only).
    ///         Accrued interest is captured by calling `balanceOf` instead.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Returns the current supply rate per second (scaled by 1e18).
    /// @param  utilization  Current utilization ratio (scaled by 1e18)
    function getSupplyRate(uint256 utilization) external view returns (uint64);

    /// @notice Returns the current market utilization ratio scaled by 1e18.
    function getUtilization() external view returns (uint256);
}

/// @title CompoundV3Adapter
/// @notice IYieldSource implementation that supplies USDC to Compound V3 (Comet)
///         and withdraws on demand.
/// @dev    Compound V3 does NOT use a separate receipt token — the supplier's
///         balance is tracked inside Comet directly.  `balanceOf(address(this))`
///         on the Comet contract returns this adapter's total balance including
///         accrued interest.
///
///         Rate calculation:
///           Comet exposes a per-second rate (uint64, scaled 1e18).
///           APY ≈ ratePerSec * SECONDS_PER_YEAR, then converted to bps.
contract CompoundV3Adapter is IYieldSource, Ownable {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 private constant SECONDS_PER_YEAR = 365 days;

    /// @dev  1e18 scaling factor used by Comet's rate calculations
    uint256 private constant RATE_SCALE = 1e18;

    /// @dev  10_000 basis points == 100%
    uint256 private constant BPS = 10_000;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice Compound V3 Comet contract (USDC market)
    IComet public immutable comet;

    /// @notice Underlying ERC-20 (USDC)
    IERC20 private immutable _asset;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Single address authorised to call deposit / withdraw
    address public authorizedCaller;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error Unauthorized();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event AuthorizedCallerUpdated(address indexed previous, address indexed next);

    // -------------------------------------------------------------------------
    // Modifier
    // -------------------------------------------------------------------------

    modifier onlyAuthorized() {
        if (msg.sender != authorizedCaller) revert Unauthorized();
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _comet        Compound V3 Comet market address
    /// @param assetAddress  Underlying ERC-20 (USDC)
    /// @param _owner        Admin owner
    constructor(address _comet, address assetAddress, address _owner) Ownable(_owner) {
        comet = IComet(_comet);
        _asset = IERC20(assetAddress);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /// @notice Updates the authorised caller.
    ///         Should be the YieldRouter contract address.
    function setAuthorizedCaller(address caller) external onlyOwner {
        emit AuthorizedCallerUpdated(authorizedCaller, caller);
        authorizedCaller = caller;
    }

    // -------------------------------------------------------------------------
    // IYieldSource — mutative
    // -------------------------------------------------------------------------

    /// @inheritdoc IYieldSource
    /// @dev  Transfers USDC from the caller, approves Comet, then calls supply().
    ///       Comet accounts the deposit directly to this adapter's address.
    function deposit(uint256 amount) external onlyAuthorized returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();
        if (amount > maxDeposit()) revert ExceedsCapacity(amount, maxDeposit());

        _asset.safeTransferFrom(msg.sender, address(this), amount);
        _asset.forceApprove(address(comet), amount);
        comet.supply(address(_asset), amount);

        // Compound V3 uses 1:1 accounting for the base asset;
        // return `amount` as the "shares" to keep the interface consistent.
        shares = amount;
        emit Deposited(msg.sender, amount, shares);
    }

    /// @inheritdoc IYieldSource
    /// @dev  Calls Comet.withdraw() which sends tokens directly to msg.sender
    ///       (the authorised caller / YieldRouter).
    function withdraw(uint256 amount) external onlyAuthorized returns (uint256 received) {
        if (amount == 0) revert ZeroAmount();

        uint256 before = _asset.balanceOf(msg.sender);
        comet.withdraw(address(_asset), amount);
        // Transfer out to caller (Comet sends tokens to this contract, not caller)
        uint256 withdrawn = _asset.balanceOf(address(this));
        if (withdrawn > 0) {
            _asset.safeTransfer(msg.sender, withdrawn);
        }
        received = _asset.balanceOf(msg.sender) - before;
        emit Withdrawn(msg.sender, amount, received);
    }

    /// @inheritdoc IYieldSource
    function withdrawAll() external onlyAuthorized returns (uint256 received) {
        uint256 bal = comet.balanceOf(address(this));
        if (bal == 0) return 0;

        uint256 before = _asset.balanceOf(msg.sender);
        comet.withdraw(address(_asset), bal);
        uint256 withdrawn = _asset.balanceOf(address(this));
        if (withdrawn > 0) {
            _asset.safeTransfer(msg.sender, withdrawn);
        }
        received = _asset.balanceOf(msg.sender) - before;
        emit Withdrawn(msg.sender, bal, received);
    }

    // -------------------------------------------------------------------------
    // IYieldSource — view
    // -------------------------------------------------------------------------

    /// @inheritdoc IYieldSource
    function balanceOf(address account) external view returns (uint256) {
        if (account == authorizedCaller || account == address(this)) {
            return comet.balanceOf(address(this));
        }
        return 0;
    }

    /// @inheritdoc IYieldSource
    /// @dev  APY = getSupplyRate(utilization) * SECONDS_PER_YEAR, then scaled to bps.
    ///       ratePerSecond is in 1e18 units where 1e18 == 100% per second (never
    ///       actually that high, but that's the scale).
    ///       APY_bps = ratePerSec * SECONDS_PER_YEAR * BPS / RATE_SCALE
    function currentAPY() external view returns (uint256) {
        try comet.getUtilization() returns (uint256 utilization) {
            try comet.getSupplyRate(utilization) returns (uint64 ratePerSec) {
                return (uint256(ratePerSec) * SECONDS_PER_YEAR * BPS) / RATE_SCALE;
            } catch {
                return 0;
            }
        } catch {
            return 0;
        }
    }

    /// @inheritdoc IYieldSource
    function asset() external view returns (address) {
        return address(_asset);
    }

    /// @inheritdoc IYieldSource
    function maxDeposit() public pure returns (uint256) {
        return type(uint256).max;
    }
}
