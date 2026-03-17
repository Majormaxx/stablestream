// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IYieldSource} from "./interfaces/IYieldSource.sol";

/// @title YieldRouter
/// @notice Manages a set of yield adapters (Aave, Compound, …) and routes idle
///         USDC from StableStreamHook to whichever source currently offers the
///         highest APY.
///
/// @dev    Design principles:
///           - One active source per routing decision (simplest composability).
///           - Swapping sources is permissionless in direction (any source → any
///             other source) but controlled by StableStreamHook.
///           - All token movements go through SafeERC20 to handle non-standard
///             ERC-20 implementations (e.g., USDT on some chains).
///           - Emergency withdrawAll() is always available to the owner.
///
///         Source registration uses a fixed-size array capped at MAX_SOURCES to
///         bound the O(n) best-APY scan and keep gas predictable.
contract YieldRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Maximum number of yield sources that can be registered
    uint256 public constant MAX_SOURCES = 8;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Registered yield adapter addresses (may contain address(0) gaps)
    address[MAX_SOURCES] public sources;

    /// @notice Number of active (non-zero) source slots
    uint256 public sourceCount;

    /// @notice ERC-20 token managed by this router (USDC)
    IERC20 public immutable asset;

    /// @notice Address authorised to call route / recall / switchSource
    ///         (set to StableStreamHook after deployment)
    address public authorizedCaller;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error Unauthorized();
    error SourceAlreadyRegistered(address source);
    error SourceNotRegistered(address source);
    error MaxSourcesReached();
    error NoActiveSources();
    error ZeroAmount();
    error InsufficientBalance(uint256 requested, uint256 available);

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event SourceRegistered(address indexed source);
    event SourceRemoved(address indexed source);
    event Routed(address indexed source, uint256 amount);
    event Recalled(address indexed source, uint256 amount, uint256 received);
    event Switched(address indexed from, address indexed to, uint256 amount);
    event AuthorizedCallerUpdated(address indexed previous, address indexed next);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyAuthorized() {
        if (msg.sender != authorizedCaller && msg.sender != owner()) revert Unauthorized();
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param assetAddress  ERC-20 underlying (USDC)
    /// @param _owner        Admin owner (typically the deployer / multisig)
    constructor(address assetAddress, address _owner) Ownable(_owner) {
        asset = IERC20(assetAddress);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /// @notice Updates the authorised caller.
    ///         Call this after deploying StableStreamHook to point it here.
    function setAuthorizedCaller(address caller) external onlyOwner {
        emit AuthorizedCallerUpdated(authorizedCaller, caller);
        authorizedCaller = caller;
    }

    /// @notice Registers a new yield adapter.
    /// @dev    Checks for duplicates to prevent double-counting.
    /// @param source  IYieldSource-compliant adapter address
    function registerSource(address source) external onlyOwner {
        if (sourceCount >= MAX_SOURCES) revert MaxSourcesReached();

        for (uint256 i = 0; i < MAX_SOURCES; i++) {
            if (sources[i] == source) revert SourceAlreadyRegistered(source);
        }

        for (uint256 i = 0; i < MAX_SOURCES; i++) {
            if (sources[i] == address(0)) {
                sources[i] = source;
                sourceCount++;
                emit SourceRegistered(source);
                return;
            }
        }
    }

    /// @notice Removes a yield adapter.
    ///         Any funds still deposited in the source are NOT automatically
    ///         recalled; the owner must do so before removing.
    /// @param source  Adapter to deregister
    function removeSource(address source) external onlyOwner {
        for (uint256 i = 0; i < MAX_SOURCES; i++) {
            if (sources[i] == source) {
                sources[i] = address(0);
                sourceCount--;
                emit SourceRemoved(source);
                return;
            }
        }
        revert SourceNotRegistered(source);
    }

    // -------------------------------------------------------------------------
    // Core routing
    // -------------------------------------------------------------------------

    /// @notice Routes `amount` USDC to the highest-APY registered source.
    ///         The caller (StableStreamHook) must have approved this contract to
    ///         spend `amount` tokens before calling.
    /// @param  amount  USDC to deposit
    /// @return chosen  The yield source address that received the funds
    function routeToBestSource(uint256 amount)
        external
        onlyAuthorized
        nonReentrant
        returns (address chosen)
    {
        if (amount == 0) revert ZeroAmount();
        if (sourceCount == 0) revert NoActiveSources();

        chosen = _bestSource(amount);

        // Pull tokens from caller
        asset.safeTransferFrom(msg.sender, address(this), amount);
        // Approve adapter to spend
        asset.forceApprove(chosen, amount);
        // Deposit into adapter
        IYieldSource(chosen).deposit(amount);

        emit Routed(chosen, amount);
    }

    /// @notice Deposits `amount` USDC into a specific source.
    ///         Used when the RSC specifies an explicit target rather than letting
    ///         the router choose.
    /// @param source  Target yield adapter
    /// @param amount  USDC to deposit
    function routeToSource(address source, uint256 amount)
        external
        onlyAuthorized
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        _requireRegistered(source);

        asset.safeTransferFrom(msg.sender, address(this), amount);
        asset.forceApprove(source, amount);
        IYieldSource(source).deposit(amount);

        emit Routed(source, amount);
    }

    /// @notice Withdraws `amount` USDC from `source` and sends it to `recipient`.
    /// @param source     Adapter to withdraw from
    /// @param amount     Underlying tokens to redeem
    /// @param recipient  Address to receive the tokens
    /// @return received  Actual tokens received (may be slightly less due to fees)
    function recallFromSource(address source, uint256 amount, address recipient)
        external
        onlyAuthorized
        nonReentrant
        returns (uint256 received)
    {
        if (amount == 0) revert ZeroAmount();
        _requireRegistered(source);

        uint256 available = IYieldSource(source).balanceOf(address(this));
        if (available < amount) revert InsufficientBalance(amount, available);

        received = IYieldSource(source).withdraw(amount);

        // Forward withdrawn tokens to recipient
        asset.safeTransfer(recipient, received);

        emit Recalled(source, amount, received);
    }

    /// @notice Withdraws ALL funds from `source` and sends to `recipient`.
    ///         Called during emergency or full-position withdrawal.
    /// @param source     Adapter to drain
    /// @param recipient  Address to receive all tokens
    /// @return received  Total tokens returned
    function recallAllFromSource(address source, address recipient)
        external
        onlyAuthorized
        nonReentrant
        returns (uint256 received)
    {
        _requireRegistered(source);

        received = IYieldSource(source).withdrawAll();
        if (received > 0) {
            asset.safeTransfer(recipient, received);
        }

        emit Recalled(source, type(uint256).max, received);
    }

    /// @notice Moves all funds from `fromSource` to `toSource` atomically.
    ///         Used when the RSC detects a better APY opportunity.
    /// @param fromSource  Current yield source
    /// @param toSource    Target yield source
    function switchSource(address fromSource, address toSource)
        external
        onlyAuthorized
        nonReentrant
    {
        _requireRegistered(fromSource);
        _requireRegistered(toSource);

        uint256 recalled = IYieldSource(fromSource).withdrawAll();
        if (recalled == 0) return;

        asset.forceApprove(toSource, recalled);
        IYieldSource(toSource).deposit(recalled);

        emit Switched(fromSource, toSource, recalled);
    }

    // -------------------------------------------------------------------------
    // Emergency
    // -------------------------------------------------------------------------

    /// @notice Owner-only emergency drain of all registered sources.
    ///         Sends all recovered tokens to `recipient`.
    function emergencyWithdrawAll(address recipient) external onlyOwner nonReentrant {
        for (uint256 i = 0; i < MAX_SOURCES; i++) {
            address src = sources[i];
            if (src == address(0)) continue;

            uint256 bal = IYieldSource(src).balanceOf(address(this));
            if (bal == 0) continue;

            try IYieldSource(src).withdrawAll() returns (uint256 received) {
                if (received > 0) {
                    asset.safeTransfer(recipient, received);
                }
            } catch {
                // Log via event and continue — never revert in an emergency drain
                emit Recalled(src, bal, 0);
            }
        }
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /// @notice Returns the total value (across all sources) managed by this router.
    function totalBalance() external view returns (uint256 total) {
        for (uint256 i = 0; i < MAX_SOURCES; i++) {
            address src = sources[i];
            if (src == address(0)) continue;
            total += IYieldSource(src).balanceOf(address(this));
        }
    }

    /// @notice Returns the address of the source currently offering the highest APY.
    /// @param  minAmount  Minimum deposit size (filters out sources that can't accept it)
    /// @return best       Address of the best source, or address(0) if none available
    function bestSource(uint256 minAmount) external view returns (address best) {
        return _bestSource(minAmount);
    }

    /// @notice Returns APYs (in bps) for all registered sources in order.
    function allAPYs() external view returns (address[] memory addrs, uint256[] memory apys) {
        addrs = new address[](MAX_SOURCES);
        apys = new uint256[](MAX_SOURCES);
        for (uint256 i = 0; i < MAX_SOURCES; i++) {
            addrs[i] = sources[i];
            if (sources[i] != address(0)) {
                try IYieldSource(sources[i]).currentAPY() returns (uint256 apy) {
                    apys[i] = apy;
                } catch {
                    apys[i] = 0;
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _bestSource(uint256 minAmount) internal view returns (address best) {
        uint256 bestAPY;
        for (uint256 i = 0; i < MAX_SOURCES; i++) {
            address src = sources[i];
            if (src == address(0)) continue;

            // Skip sources that can't accept the full deposit
            if (IYieldSource(src).maxDeposit() < minAmount) continue;

            uint256 apy;
            try IYieldSource(src).currentAPY() returns (uint256 a) {
                apy = a;
            } catch {
                apy = 0;
            }

            if (apy > bestAPY) {
                bestAPY = apy;
                best = src;
            }
        }
        if (best == address(0)) revert NoActiveSources();
    }

    function _requireRegistered(address source) internal view {
        for (uint256 i = 0; i < MAX_SOURCES; i++) {
            if (sources[i] == source) return;
        }
        revert SourceNotRegistered(source);
    }
}
