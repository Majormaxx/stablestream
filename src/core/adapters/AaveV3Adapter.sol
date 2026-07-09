// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IYieldSource} from "../interfaces/IYieldSource.sol";

// ---------------------------------------------------------------------------
// Minimal Aave V3 interfaces — only the functions we use
// ---------------------------------------------------------------------------

/// @dev Aave V3 Pool contract (also used on Unichain via Aave's deployment)
interface IAaveV3Pool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
        external;

    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

/// @dev Aave V3 data-provider — used to fetch the current supply rate
interface IAaveV3DataProvider {
    /// @notice Returns reserve data; the sixth value is the ray-denominated supply rate.
    function getReserveData(address asset)
        external
        view
        returns (
            uint256 unbacked,
            uint256 accruedToTreasuryScaled,
            uint256 totalAToken,
            uint256 totalStableDebt,
            uint256 totalVariableDebt,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 stableBorrowRate,
            uint256 averageStableBorrowRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            uint40 lastUpdateTimestamp
        );
}

/// @title AaveV3Adapter
/// @notice IYieldSource implementation that supplies USDC to Aave V3 and
///         redeems aUSDC shares on demand.
/// @dev    Only the authorised caller (StableStreamHook or YieldRouter) may
///         invoke mutative functions.  This prevents any external actor from
///         draining the adapter's aToken balance.
///
///         Yield accounting note: aTokens are rebasing — aUSDC balance grows
///         automatically each block.  `balanceOf` therefore reads the live
///         aToken balance, capturing all accrued interest without any
///         manual bookkeeping.
contract AaveV3Adapter is IYieldSource, Ownable {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants / immutables
    // -------------------------------------------------------------------------

    /// @notice 1 ray = 1e27, used for Aave's rate normalisation
    uint256 private constant RAY = 1e27;

    /// @notice Aave V3 Pool contract on Unichain (set at deploy time)
    IAaveV3Pool public immutable pool;

    /// @notice Aave V3 Protocol Data Provider (for APY reads)
    IAaveV3DataProvider public immutable dataProvider;

    /// @notice aUSDC rebasing token issued by Aave
    IERC20 public immutable aToken;

    /// @notice Underlying asset managed by this adapter (USDC)
    IERC20 private immutable _asset;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice The single authorised caller that may deposit / withdraw
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
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyAuthorized() {
        if (msg.sender != authorizedCaller) revert Unauthorized();
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _pool          Aave V3 Pool address on the target network
    /// @param _dataProvider  Aave V3 Protocol Data Provider address
    /// @param _aToken        aUSDC address corresponding to the underlying
    /// @param assetAddress   Underlying ERC-20 (USDC)
    /// @param _owner         Contract owner (admin)
    constructor(
        address _pool,
        address _dataProvider,
        address _aToken,
        address assetAddress,
        address _owner
    ) Ownable(_owner) {
        pool = IAaveV3Pool(_pool);
        dataProvider = IAaveV3DataProvider(_dataProvider);
        aToken = IERC20(_aToken);
        _asset = IERC20(assetAddress);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /// @notice Sets the only address permitted to call deposit / withdraw.
    ///         Typically the YieldRouter contract.
    /// @param caller  New authorised caller
    function setAuthorizedCaller(address caller) external onlyOwner {
        emit AuthorizedCallerUpdated(authorizedCaller, caller);
        authorizedCaller = caller;
    }

    // -------------------------------------------------------------------------
    // IYieldSource — mutative
    // -------------------------------------------------------------------------

    /// @inheritdoc IYieldSource
    /// @dev  Pulls `amount` USDC from msg.sender, supplies to Aave, credits
    ///       aUSDC to this contract.  The caller must approve this adapter
    ///       prior to calling.
    function deposit(uint256 amount) external onlyAuthorized returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();
        if (amount > maxDeposit()) revert ExceedsCapacity(amount, maxDeposit());

        _asset.safeTransferFrom(msg.sender, address(this), amount);
        _asset.forceApprove(address(pool), amount);

        uint256 before = aToken.balanceOf(address(this));
        pool.supply(address(_asset), amount, address(this), 0);
        shares = aToken.balanceOf(address(this)) - before;

        emit Deposited(msg.sender, amount, shares);
    }

    /// @inheritdoc IYieldSource
    /// @dev  Redeems up to `amount` USDC from Aave and transfers it to msg.sender.
    ///       If `amount` > current balance, Aave will revert — callers should
    ///       query `balanceOf` first.
    function withdraw(uint256 amount) external onlyAuthorized returns (uint256 received) {
        if (amount == 0) revert ZeroAmount();

        received = pool.withdraw(address(_asset), amount, msg.sender);
        emit Withdrawn(msg.sender, amount, received);
    }

    /// @inheritdoc IYieldSource
    function withdrawAll() external onlyAuthorized returns (uint256 received) {
        uint256 bal = aToken.balanceOf(address(this));
        if (bal == 0) return 0;

        // type(uint256).max signals Aave to redeem all aTokens
        received = pool.withdraw(address(_asset), type(uint256).max, msg.sender);
        emit Withdrawn(msg.sender, bal, received);
    }

    // -------------------------------------------------------------------------
    // IYieldSource — view
    // -------------------------------------------------------------------------

    /// @inheritdoc IYieldSource
    /// @dev  Returns the live aToken balance of this contract.
    ///       aTokens rebase each block, so this automatically includes yield.
    function balanceOf(address account) external view returns (uint256) {
        // Only this contract holds aTokens on behalf of all tracked positions;
        // the account parameter is accepted for interface compatibility but the
        // single-adapter design means we always return this contract's balance
        // when account == authorizedCaller or address(this).
        if (account == authorizedCaller || account == address(this)) {
            return aToken.balanceOf(address(this));
        }
        return 0;
    }

    /// @inheritdoc IYieldSource
    /// @dev  Converts Aave's ray-denominated liquidityRate to basis points.
    ///       liquidityRate is an annual rate where 1 RAY = 100%.
    ///       bps = liquidityRate * 10_000 / RAY
    function currentAPY() external view returns (uint256) {
        try dataProvider.getReserveData(address(_asset)) returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256 liquidityRate,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint40
        ) {
            // liquidityRate is in ray (1e27 = 100%).  Convert to bps (10_000 = 100%).
            return (liquidityRate * 10_000) / RAY;
        } catch {
            // Return 0 on failure so YieldRouter can still compare sources
            return 0;
        }
    }

    /// @inheritdoc IYieldSource
    function asset() external view returns (address) {
        return address(_asset);
    }

    /// @inheritdoc IYieldSource
    /// @dev  Aave V3 has no hard deposit cap exposed via a simple call.
    ///       Returning max uint256 means YieldRouter treats it as unlimited.
    function maxDeposit() public pure returns (uint256) {
        return type(uint256).max;
    }
}
