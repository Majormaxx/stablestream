// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IYieldSource} from "./interfaces/IYieldSource.sol";
import {APYVerifier} from "./libraries/APYVerifier.sol";
import {RiskEngine} from "./libraries/RiskEngine.sol";

/// @title YieldRouter
/// @notice Manages a set of yield adapters (Aave, Compound, …) and routes idle
///         USDC from StableStreamHook to whichever source currently offers the
///         highest risk-adjusted APY.
///
/// @dev    Design principles:
///           - One active source per routing decision (simplest composability).
///           - Swapping sources is permissionless in direction (any source → any
///             other source) but controlled by StableStreamHook.
///           - All token movements go through SafeERC20 to handle non-standard
///             ERC-20 implementations (e.g., USDT on some chains).
///           - Emergency withdrawAll() is always available to the owner.
///           - APYVerifier rejects sources reporting anomalous APY spikes.
///           - RiskEngine filters sources by LP risk tolerance and adjusts APY
///             by a safety multiplier.
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

    /// @notice Default LP risk tolerance used by routeToBestSource().
    ///         5 → maxRisk = 100, which accepts every source regardless of its riskScore.
    uint8 public constant DEFAULT_RISK_TOLERANCE = 5;

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

    /// @notice Per-source rolling APY snapshot for TWAP anomaly detection (WS4)
    mapping(address source => APYVerifier.APYSnapshot) public apySnapshots;

    /// @notice Per-source risk profile for risk-weighted routing (WS5)
    mapping(address source => RiskEngine.RiskProfile) public sourceRiskProfiles;

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
    event RiskProfileSet(address indexed source, uint16 riskScore, uint8 tvlTier);
    event APYSnapshotSeeded(address indexed source, uint256 seedAPY);

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
    // Admin — source management
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
    // Admin — risk profiles (WS5)
    // -------------------------------------------------------------------------

    /// @notice Set or update the risk profile for a registered yield source.
    ///
    /// @dev    riskScore encodes the owner's assessment of smart contract risk,
    ///         oracle dependence, and liquidity risk.  Range: 0 (safest) – 100 (riskiest).
    ///         See RiskEngine.RiskProfile for field documentation.
    ///
    /// @param source   Registered yield adapter
    /// @param profile  Risk metadata struct
    function setRiskProfile(address source, RiskEngine.RiskProfile calldata profile)
        external
        onlyOwner
    {
        _requireRegistered(source);
        sourceRiskProfiles[source] = profile;
        emit RiskProfileSet(source, profile.riskScore, profile.tvlTier);
    }

    // -------------------------------------------------------------------------
    // Admin — APY snapshots (WS4)
    // -------------------------------------------------------------------------

    /// @notice Seed the APY snapshot for a source with an initial known-good value.
    ///         Should be called after registering a new source so the TWAP has
    ///         baseline data before the first routing call.
    ///
    /// @dev    Seeds two identical readings so isWithinBounds() has ≥ 2 samples
    ///         immediately and can perform anomaly detection from the first call.
    ///
    /// @param source   Registered yield adapter
    /// @param seedAPY  Known-good APY in basis points (e.g. 320 = 3.20%)
    function initializeAPYSnapshot(address source, uint256 seedAPY) external onlyOwner {
        _requireRegistered(source);
        APYVerifier.update(apySnapshots[source], seedAPY);
        APYVerifier.update(apySnapshots[source], seedAPY); // two identical readings for bootstrap
        emit APYSnapshotSeeded(source, seedAPY);
    }

    // -------------------------------------------------------------------------
    // Core routing
    // -------------------------------------------------------------------------

    /// @notice Routes `amount` USDC to the highest risk-adjusted APY source.
    ///         Uses DEFAULT_RISK_TOLERANCE (5 = accept any source).
    ///
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

        chosen = _bestSource(amount, DEFAULT_RISK_TOLERANCE);

        // Pull tokens from caller
        asset.safeTransferFrom(msg.sender, address(this), amount);
        // Approve adapter to spend
        asset.forceApprove(chosen, amount);
        // Deposit into adapter
        IYieldSource(chosen).deposit(amount);

        emit Routed(chosen, amount);
    }

    /// @notice Routes `amount` to the highest source meeting the given risk tolerance.
    ///
    /// @param  amount         USDC to deposit
    /// @param  riskTolerance  LP's risk tolerance 0–5 (5 = accept any source)
    /// @return chosen         The yield source address that received the funds
    function routeToBestSourceWithRisk(uint256 amount, uint8 riskTolerance)
        external
        onlyAuthorized
        nonReentrant
        returns (address chosen)
    {
        if (amount == 0) revert ZeroAmount();
        if (sourceCount == 0) revert NoActiveSources();

        chosen = _bestSource(amount, riskTolerance);

        asset.safeTransferFrom(msg.sender, address(this), amount);
        asset.forceApprove(chosen, amount);
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

    /// @notice Returns the address of the best source at DEFAULT_RISK_TOLERANCE.
    ///         Non-view: also records sampled APYs into the TWAP buffer.
    /// @param  minAmount  Minimum deposit size filter
    function bestSource(uint256 minAmount) external returns (address) {
        return _bestSource(minAmount, DEFAULT_RISK_TOLERANCE);
    }

    /// @notice Returns the best source for a given risk tolerance.
    ///         Non-view: also records sampled APYs into the TWAP buffer.
    /// @param  minAmount      Minimum deposit size filter
    /// @param  riskTolerance  LP's risk tolerance 0–5
    function bestSourceWithRisk(uint256 minAmount, uint8 riskTolerance)
        external
        returns (address)
    {
        return _bestSource(minAmount, riskTolerance);
    }

    /// @notice Returns raw and TWAP APYs for all registered sources.
    function allAPYs()
        external
        view
        returns (address[] memory addrs, uint256[] memory apys, uint256[] memory twaps)
    {
        addrs = new address[](MAX_SOURCES);
        apys  = new uint256[](MAX_SOURCES);
        twaps = new uint256[](MAX_SOURCES);

        for (uint256 i = 0; i < MAX_SOURCES; i++) {
            addrs[i] = sources[i];
            if (sources[i] == address(0)) continue;

            try IYieldSource(sources[i]).currentAPY() returns (uint256 apy) {
                apys[i] = apy;
            } catch {
                apys[i] = 0;
            }
            twaps[i] = APYVerifier.twap(apySnapshots[sources[i]]);  // explicit lib call
        }
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @notice Core best-source selection with APY verification and risk filtering.
    ///
    /// @dev    Algorithm:
    ///           For each registered source:
    ///             1. Skip if maxDeposit() < minAmount.
    ///             2. Query currentAPY(); skip if adapter reverts.
    ///             3. APY anomaly check via TWAP (skip if outside bounds).
    ///             4. Update APY snapshot.
    ///             5. Risk filter: skip if riskScore > lpTolerance × 20.
    ///             6. Compute risk-adjusted APY.
    ///             7. Track the source with the highest adjusted APY.
    ///
    /// @param minAmount      Minimum USDC the chosen source must accept
    /// @param riskTolerance  LP's risk tolerance 0–5 (5 = no filter)
    /// @return best          Address of the winning source
    function _bestSource(uint256 minAmount, uint8 riskTolerance)
        internal
        returns (address best)
    {
        uint256 bestScore;

        for (uint256 i = 0; i < MAX_SOURCES; i++) {
            address src = sources[i];
            if (src == address(0)) continue;

            // Capacity check (try/catch: a reverting maxDeposit skips the source, not routing)
            uint256 cap;
            try IYieldSource(src).maxDeposit() returns (uint256 c) {
                cap = c;
            } catch {
                continue;
            }
            if (cap < minAmount) continue;

            // Query APY (safe — adapters may revert)
            uint256 apy;
            try IYieldSource(src).currentAPY() returns (uint256 a) {
                apy = a;
            } catch {
                apy = 0;
            }

            // APY anomaly detection via TWAP: reject sources reporting suspicious spikes.
            if (!APYVerifier.isWithinBounds(apySnapshots[src], apy)) continue;

            // Record the observed APY into the rolling snapshot so the TWAP stays
            // current (Finding 222157ab: snapshots were never updated during routing).
            APYVerifier.update(apySnapshots[src], apy);

            // Risk filter: skip sources exceeding the LP's tolerance
            RiskEngine.RiskProfile memory profile = sourceRiskProfiles[src];
            if (!RiskEngine.meetsThreshold(profile, riskTolerance)) continue;

            // Risk-adjusted APY (penalises high-risk sources)
            uint256 adjusted = RiskEngine.riskAdjustedAPY(apy, profile);

            if (adjusted > bestScore) {
                bestScore = adjusted;
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
