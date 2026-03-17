// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// v4-periphery base contracts (BaseHook was removed in newer v4-periphery releases;
// we compose SafeCallback + IHooks manually instead)
import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";
import {ImmutableState} from "v4-periphery/src/base/ImmutableState.sol";

// v4-core interfaces and types
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

// OpenZeppelin (sourced from v4-core's submodule)
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// StableStream internals
import {YieldRouter} from "./YieldRouter.sol";
import {RangeCalculator} from "./libraries/RangeCalculator.sol";
import {YieldAccounting} from "./libraries/YieldAccounting.sol";

/// @title StableStreamHook
/// @notice Uniswap v4 hook that automatically routes idle USDC from out-of-range
///         concentrated liquidity positions to external yield protocols (Aave V3,
///         Compound V3) and recalls capital just-in-time when swaps re-enter a
///         position's price range.
///
/// @dev    Architecture
///         ────────────
///         Users deposit USDC through this contract (not directly to PoolManager).
///         The hook acts as a *delegated position manager* for stablecoin LPs:
///
///           1. deposit()             — user USDC → hook → add liquidity in pool
///           2. afterSwap()           — detects out-of-range positions, emits events
///           3. beforeSwap()          — flags positions needing JIT recall
///           4. RSC (Reactive Net.)   — watches events, calls routeToYield() / recallFromYield()
///           5. routeToYield()        — remove idle liquidity → deposit in yield source
///           6. recallFromYield()     — withdraw from yield → re-add liquidity to pool
///           7. withdraw()            — LP exits; returns capital + accrued yield
///
///         Hook callbacks are intentionally lightweight (no external calls inside
///         PoolManager's execution context) because v4 blocks reentrancy into the
///         pool during callbacks.  All heavy operations go through the external
///         functions triggered by the Reactive Smart Contract.
///
///         Position ID
///         ───────────
///         positionId = keccak256(abi.encode(owner, poolId, tickLower, tickUpper))
///
/// @custom:security-contact security@stablestream.xyz
contract StableStreamHook is IHooks, SafeCallback, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using YieldAccounting for YieldAccounting.YieldState;

    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    /// @notice Internal action codes encoded into poolManager.unlock() calldata
    enum Action {
        DEPOSIT,
        WITHDRAW,
        ROUTE_TO_YIELD,
        RECALL_FROM_YIELD
    }

    /// @notice Full on-chain state of a tracked LP position
    struct TrackedPosition {
        /// @dev  LP who deposited (receives capital + yield on exit)
        address owner;
        /// @dev  Pool this position belongs to
        PoolId poolId;
        /// @dev  Concentrated range lower tick
        int24 tickLower;
        /// @dev  Concentrated range upper tick
        int24 tickUpper;
        /// @dev  Liquidity units currently active in the pool (0 when routed to yield)
        uint128 liquidity;
        /// @dev  USDC currently in a yield source (0 when active in pool)
        uint256 yieldDeposited;
        /// @dev  Which yield adapter currently holds the capital
        address activeYieldSource;
        /// @dev  Per-position yield accounting
        YieldAccounting.YieldState yieldState;
        /// @dev  True when the position has been fully exited
        bool closed;
        /// @dev  Stored PoolKey so re-adding liquidity doesn't require the LP to supply it
        PoolKey key;
    }

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Minimum seconds between consecutive routing actions on the same position.
    ///         Prevents gas waste when the tick oscillates rapidly near a range boundary.
    uint256 public constant ROUTE_COOLDOWN = 60 seconds;

    // -------------------------------------------------------------------------
    // Immutable state
    // -------------------------------------------------------------------------

    /// @notice YieldRouter that selects and interacts with yield adapters
    YieldRouter public immutable yieldRouter;

    /// @notice USDC ERC-20 token managed by this hook
    IERC20 public immutable usdc;

    // -------------------------------------------------------------------------
    // Mutable state
    // -------------------------------------------------------------------------

    /// @notice Positions indexed by their unique ID
    mapping(bytes32 positionId => TrackedPosition) public positions;

    /// @notice All position IDs belonging to an owner (for enumeration)
    mapping(address owner => bytes32[]) public ownerPositions;

    /// @notice Per-pool ordered list of position IDs (for O(n) scans in callbacks)
    /// @dev    In production, replace with a doubly-linked list to keep gas bounded.
    ///         For the hackathon, stablecoin pools typically hold few managed positions.
    mapping(PoolId poolId => bytes32[]) private _poolPositionIds;

    /// @notice Last-known tick per pool, updated on every afterSwap
    mapping(PoolId poolId => int24) private _prevTicks;

    /// @notice Set to true in beforeSwap when a swap would re-enter a position's range.
    ///         The RSC watches this flag and calls recallFromYield() in the next block.
    mapping(bytes32 positionId => bool) public pendingRecall;

    /// @notice Address of the Reactive Smart Contract authorised to call routing functions
    address public reactiveContract;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NotOwnerOfPosition(bytes32 positionId);
    error PositionAlreadyExists(bytes32 positionId);
    error PositionNotFound(bytes32 positionId);
    error PositionAlreadyClosed(bytes32 positionId);
    error PositionCurrentlyInRange(bytes32 positionId);
    error PositionAlreadyRouted(bytes32 positionId);
    error PositionNotRouted(bytes32 positionId);
    error RoutingCooldownActive(bytes32 positionId, uint256 unlocksAt);
    error UnauthorizedRoutingCaller();
    error ZeroAmount();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a new position is opened via deposit()
    event PositionOpened(
        bytes32 indexed positionId,
        address indexed owner,
        PoolId indexed poolId,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    );

    /// @notice Emitted when afterSwap detects a position exited its active range.
    ///         The RSC watches this to trigger routeToYield().
    event PositionLeftRange(bytes32 indexed positionId, int24 newTick);

    /// @notice Emitted when beforeSwap or afterSwap detects a swap will/did re-enter range.
    ///         The RSC watches this to trigger recallFromYield() JIT.
    event PositionEnteredRange(bytes32 indexed positionId, int24 currentTick);

    /// @notice Emitted after capital is successfully routed to a yield source
    event CapitalRouted(
        bytes32 indexed positionId,
        address indexed yieldSource,
        uint256 amount
    );

    /// @notice Emitted after capital is recalled from a yield source and re-added as liquidity
    event CapitalRecalled(
        bytes32 indexed positionId,
        address indexed yieldSource,
        uint256 received,
        uint128 newLiquidity
    );

    /// @notice Emitted when a position is fully withdrawn
    event PositionExited(
        bytes32 indexed positionId,
        address indexed owner,
        uint256 usdcReturned,
        uint256 yieldEarned
    );

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _poolManager  Uniswap v4 PoolManager
    /// @param _yieldRouter  Deployed YieldRouter (must have this hook as authorizedCaller)
    /// @param _usdc         USDC ERC-20 address (6 decimals on Unichain)
    /// @param _owner        Admin owner (multisig in production)
    constructor(
        IPoolManager _poolManager,
        YieldRouter _yieldRouter,
        address _usdc,
        address _owner
    ) SafeCallback(_poolManager) Ownable(_owner) {
        yieldRouter = _yieldRouter;
        usdc = IERC20(_usdc);
    }

    // -------------------------------------------------------------------------
    // IHooks — permission declaration
    // -------------------------------------------------------------------------

    /// @notice Returns the set of hook callbacks this contract implements.
    ///         The hook address must be mined (or computed via CREATE2) so that
    ///         the address bits match these flags exactly.
    ///         See Hooks.sol in v4-core for the bit layout.
    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,       // register / track deposits
            beforeRemoveLiquidity: true,   // block direct removal when capital is in yield
            afterRemoveLiquidity: false,
            beforeSwap: true,              // flag positions for JIT recall
            afterSwap: true,               // detect range-exit events
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -------------------------------------------------------------------------
    // IHooks — callbacks (only the four we declared above are active)
    // -------------------------------------------------------------------------

    /// @inheritdoc IHooks
    function beforeInitialize(address, PoolKey calldata, uint160)
        external
        pure
        returns (bytes4)
    {
        return IHooks.beforeInitialize.selector;
    }

    /// @inheritdoc IHooks
    function afterInitialize(address, PoolKey calldata, uint160, int24)
        external
        pure
        returns (bytes4)
    {
        return IHooks.afterInitialize.selector;
    }

    /// @inheritdoc IHooks
    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return IHooks.beforeAddLiquidity.selector;
    }

    /// @inheritdoc IHooks
    /// @dev  Called after any liquidity addition on a pool that references this hook.
    ///       When the call originates from our own deposit() flow (hookData == true),
    ///       we skip redundant registration because deposit() already registers the position.
    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4, BalanceDelta) {
        // hookData == abi.encode(true) signals an internal deposit; skip extra work.
        if (hookData.length == 32) {
            bool internal_ = abi.decode(hookData, (bool));
            if (internal_) {
                return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
            }
        }
        return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /// @inheritdoc IHooks
    /// @dev  Blocks direct liquidity removal when the position's capital is in a yield
    ///       source.  Forces LPs to go through withdraw(), which recalls capital first.
    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) external onlyPoolManager returns (bytes4) {
        bytes32 posId = _positionId(sender, key.toId(), params.tickLower, params.tickUpper);
        TrackedPosition storage pos = positions[posId];

        if (pos.owner != address(0) && !pos.closed && pos.yieldDeposited > 0) {
            revert("StableStream: capital is in yield; call withdraw() instead");
        }

        return IHooks.beforeRemoveLiquidity.selector;
    }

    /// @inheritdoc IHooks
    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /// @inheritdoc IHooks
    /// @dev  Lightweight pre-swap scan: flags out-of-yield positions that a swap might
    ///       re-enter, so the RSC can execute a JIT recall before the next block.
    ///       We intentionally do NOT call YieldRouter here — PoolManager's reentrancy
    ///       lock prevents external calls that loop back into the pool.
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId pid = key.toId();
        (, int24 currentTick,,) = poolManager.getSlot0(pid);

        bytes32[] storage poolIds = _poolPositionIds[pid];
        uint256 len = poolIds.length;

        for (uint256 i = 0; i < len; ) {
            bytes32 pid_ = poolIds[i];
            TrackedPosition storage pos = positions[pid_];

            if (!pos.closed && pos.yieldDeposited > 0 && !pendingRecall[pid_]) {
                bool couldEnter = RangeCalculator.swapCouldEnterRange(
                    currentTick,
                    params.zeroForOne,
                    params.sqrtPriceLimitX96,
                    pos.tickLower,
                    pos.tickUpper
                );
                if (couldEnter) {
                    pendingRecall[pid_] = true;
                    emit PositionEnteredRange(pid_, currentTick);
                }
            }

            unchecked { ++i; }
        }

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @inheritdoc IHooks
    /// @dev  Post-swap scan: detects which in-pool positions just left their range
    ///       and emits PositionLeftRange for the RSC to act on.
    ///       Also stores the new tick as prevTick for the next swap's beforeSwap.
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, int128) {
        PoolId pid = key.toId();
        (, int24 newTick,,) = poolManager.getSlot0(pid);
        int24 prevTick = _prevTicks[pid];
        _prevTicks[pid] = newTick;

        bytes32[] storage poolIds = _poolPositionIds[pid];
        uint256 len = poolIds.length;

        for (uint256 i = 0; i < len; ) {
            bytes32 pid_ = poolIds[i];
            TrackedPosition storage pos = positions[pid_];

            if (!pos.closed && pos.liquidity > 0) {
                if (RangeCalculator.crossedOutOfRange(prevTick, newTick, pos.tickLower, pos.tickUpper)) {
                    emit PositionLeftRange(pid_, newTick);
                }
            }

            unchecked { ++i; }
        }

        return (IHooks.afterSwap.selector, 0);
    }

    /// @inheritdoc IHooks
    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.beforeDonate.selector;
    }

    /// @inheritdoc IHooks
    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.afterDonate.selector;
    }

    // -------------------------------------------------------------------------
    // User-facing: deposit
    // -------------------------------------------------------------------------

    /// @notice Opens a new managed LP position.
    ///         Transfers USDC from the caller, adds concentrated liquidity to the
    ///         specified pool range, and registers the position for yield routing.
    ///
    /// @param  key         Uniswap v4 PoolKey (must reference this hook)
    /// @param  tickLower   Lower price tick for the position
    /// @param  tickUpper   Upper price tick for the position
    /// @param  usdcAmount  USDC to deposit (6-decimal units)
    /// @return positionId  Unique bytes32 identifier for this position
    function deposit(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        uint256 usdcAmount
    ) external nonReentrant returns (bytes32 positionId) {
        if (usdcAmount == 0) revert ZeroAmount();

        positionId = _positionId(msg.sender, key.toId(), tickLower, tickUpper);
        if (positions[positionId].owner != address(0)) {
            revert PositionAlreadyExists(positionId);
        }

        // Pull USDC from LP
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);

        // Add liquidity through PoolManager's unlock mechanism
        bytes memory result = poolManager.unlock(
            abi.encode(Action.DEPOSIT, msg.sender, key, tickLower, tickUpper, usdcAmount, positionId)
        );
        uint128 liquidity = abi.decode(result, (uint128));

        // Register position
        TrackedPosition storage pos = positions[positionId];
        pos.owner = msg.sender;
        pos.poolId = key.toId();
        pos.tickLower = tickLower;
        pos.tickUpper = tickUpper;
        pos.liquidity = liquidity;
        pos.key = key;

        ownerPositions[msg.sender].push(positionId);
        _poolPositionIds[key.toId()].push(positionId);

        emit PositionOpened(positionId, msg.sender, key.toId(), tickLower, tickUpper, liquidity);
    }

    // -------------------------------------------------------------------------
    // User-facing: withdraw
    // -------------------------------------------------------------------------

    /// @notice Closes a position and returns all capital (principal + yield) to the owner.
    ///         If capital is in a yield source, it is recalled first.
    ///
    /// @param  positionId  Position to close (must be owned by msg.sender)
    /// @return returned    Total USDC returned to the caller
    function withdraw(bytes32 positionId) external nonReentrant returns (uint256 returned) {
        TrackedPosition storage pos = positions[positionId];
        if (pos.owner == address(0)) revert PositionNotFound(positionId);
        if (pos.owner != msg.sender) revert NotOwnerOfPosition(positionId);
        if (pos.closed) revert PositionAlreadyClosed(positionId);

        uint256 beforeBal = usdc.balanceOf(address(this));

        // Recall yield-deployed capital first
        if (pos.yieldDeposited > 0 && pos.activeYieldSource != address(0)) {
            uint256 recalled = yieldRouter.recallAllFromSource(pos.activeYieldSource, address(this));
            pos.yieldState.recordWithdrawal(recalled);
            pos.yieldDeposited = 0;
            pos.activeYieldSource = address(0);
        }

        // Remove in-pool liquidity
        if (pos.liquidity > 0) {
            poolManager.unlock(abi.encode(Action.WITHDRAW, positionId));
        }

        returned = usdc.balanceOf(address(this)) - beforeBal;
        uint256 yieldEarned = uint256(pos.yieldState.harvestedYield);

        pos.closed = true;
        pos.liquidity = 0;
        pendingRecall[positionId] = false;

        if (returned > 0) {
            usdc.safeTransfer(msg.sender, returned);
        }

        emit PositionExited(positionId, msg.sender, returned, yieldEarned);
    }

    // -------------------------------------------------------------------------
    // RSC-triggered: routeToYield
    // -------------------------------------------------------------------------

    /// @notice Removes idle out-of-range liquidity from the pool and deposits it
    ///         to the highest-yielding registered source.
    ///
    /// @dev    Only callable by the registered Reactive Smart Contract or the owner.
    ///         The RSC should call this after observing a PositionLeftRange event.
    ///
    /// @param  positionId  Position whose capital should be routed
    function routeToYield(bytes32 positionId) external nonReentrant {
        if (msg.sender != reactiveContract && msg.sender != owner()) {
            revert UnauthorizedRoutingCaller();
        }

        TrackedPosition storage pos = positions[positionId];
        if (pos.owner == address(0)) revert PositionNotFound(positionId);
        if (pos.closed) revert PositionAlreadyClosed(positionId);
        if (pos.liquidity == 0) revert ZeroAmount();
        if (pos.yieldDeposited > 0) revert PositionAlreadyRouted(positionId);

        // Verify the position is genuinely out of range
        (, int24 currentTick,,) = poolManager.getSlot0(pos.poolId);
        if (RangeCalculator.isInRange(currentTick, pos.tickLower, pos.tickUpper)) {
            revert PositionCurrentlyInRange(positionId);
        }

        // Enforce routing cooldown
        if (!pos.yieldState.canRoute(ROUTE_COOLDOWN)) {
            revert RoutingCooldownActive(
                positionId,
                uint256(pos.yieldState.lastRouteTimestamp) + ROUTE_COOLDOWN
            );
        }

        // Remove liquidity from the pool (inside unlock callback)
        uint256 beforeBal = usdc.balanceOf(address(this));
        poolManager.unlock(abi.encode(Action.ROUTE_TO_YIELD, positionId));
        uint256 recovered = usdc.balanceOf(address(this)) - beforeBal;

        if (recovered == 0) return;

        // Route USDC to best yield source
        usdc.forceApprove(address(yieldRouter), recovered);
        address chosen = yieldRouter.routeToBestSource(recovered);

        pos.yieldDeposited = recovered;
        pos.activeYieldSource = chosen;
        pos.liquidity = 0;
        pos.yieldState.recordDeposit(recovered);

        emit CapitalRouted(positionId, chosen, recovered);
    }

    // -------------------------------------------------------------------------
    // RSC-triggered: recallFromYield
    // -------------------------------------------------------------------------

    /// @notice Withdraws capital from the yield source and re-adds it as active
    ///         liquidity in the pool (JIT re-entry).
    ///
    /// @dev    Only callable by the registered Reactive Smart Contract or the owner.
    ///         The RSC calls this after a PositionEnteredRange event or when
    ///         pendingRecall[positionId] is set.
    ///
    /// @param  positionId  Position to recall and re-activate
    function recallFromYield(bytes32 positionId) external nonReentrant {
        if (msg.sender != reactiveContract && msg.sender != owner()) {
            revert UnauthorizedRoutingCaller();
        }

        TrackedPosition storage pos = positions[positionId];
        if (pos.owner == address(0)) revert PositionNotFound(positionId);
        if (pos.closed) revert PositionAlreadyClosed(positionId);
        if (pos.yieldDeposited == 0) revert PositionNotRouted(positionId);

        address prevSource = pos.activeYieldSource;

        // Recall all capital from yield source
        uint256 beforeBal = usdc.balanceOf(address(this));
        yieldRouter.recallAllFromSource(prevSource, address(this));
        uint256 recalled = usdc.balanceOf(address(this)) - beforeBal;

        pos.yieldState.recordWithdrawal(recalled);
        pos.yieldDeposited = 0;
        pos.activeYieldSource = address(0);
        pendingRecall[positionId] = false;

        // Re-add as liquidity in the pool
        bytes memory result = poolManager.unlock(
            abi.encode(Action.RECALL_FROM_YIELD, positionId, recalled)
        );
        uint128 newLiquidity = abi.decode(result, (uint128));
        pos.liquidity = newLiquidity;

        emit CapitalRecalled(positionId, prevSource, recalled, newLiquidity);
    }

    // -------------------------------------------------------------------------
    // SafeCallback: unlock callback
    // -------------------------------------------------------------------------

    /// @notice Called by PoolManager when this contract invokes poolManager.unlock().
    ///         All actual pool state changes (modifyLiquidity, settle, take) happen here.
    /// @dev    msg.sender is enforced to be PoolManager by SafeCallback's onlyPoolManager.
    function _unlockCallback(bytes calldata data)
        internal
        override
        returns (bytes memory result)
    {
        Action action = abi.decode(data[:32], (Action));

        if (action == Action.DEPOSIT) {
            result = _handleDeposit(data);
        } else if (action == Action.WITHDRAW) {
            _handleWithdraw(data);
        } else if (action == Action.ROUTE_TO_YIELD) {
            _handleRouteToYield(data);
        } else if (action == Action.RECALL_FROM_YIELD) {
            result = _handleRecallFromYield(data);
        }
    }

    // -------------------------------------------------------------------------
    // Unlock callback sub-handlers
    // -------------------------------------------------------------------------

    /// @dev Adds liquidity on behalf of the depositing LP.
    ///      Settles the USDC debt owed to PoolManager after modifyLiquidity.
    function _handleDeposit(bytes calldata data) internal returns (bytes memory) {
        (
            ,
            /* Action */
            address depositor,
            PoolKey memory key,
            int24 tickLower,
            int24 tickUpper,
            uint256 usdcAmount,
            /* positionId */
        ) = abi.decode(data, (Action, address, PoolKey, int24, int24, uint256, bytes32));

        // For stablecoin pairs (USDC/USDT) the price ≈ 1.0 and liquidity ≈ amount.
        // A production implementation would use TickMath to compute the exact delta.
        int256 liquidityDelta = int256(usdcAmount);

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: liquidityDelta,
            salt: bytes32(0)
        });

        (BalanceDelta delta,) = poolManager.modifyLiquidity(key, params, abi.encode(true));

        // Settle debts: negative delta means the hook owes the pool
        _settleDeltas(key, delta);

        return abi.encode(uint128(uint256(liquidityDelta)));
    }

    /// @dev Removes liquidity and takes the returned tokens back to this contract.
    function _handleWithdraw(bytes calldata data) internal {
        (, bytes32 positionId) = abi.decode(data, (Action, bytes32));
        TrackedPosition storage pos = positions[positionId];

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: pos.tickLower,
            tickUpper: pos.tickUpper,
            liquidityDelta: -int256(uint256(pos.liquidity)),
            salt: bytes32(0)
        });

        (BalanceDelta delta,) = poolManager.modifyLiquidity(pos.key, params, bytes(""));
        _takePositiveDeltas(pos.key, delta);
        pos.liquidity = 0;
    }

    /// @dev Removes idle (out-of-range) liquidity; tokens stay in this contract
    ///      until routed to a yield source by the calling function.
    function _handleRouteToYield(bytes calldata data) internal {
        (, bytes32 positionId) = abi.decode(data, (Action, bytes32));
        TrackedPosition storage pos = positions[positionId];

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: pos.tickLower,
            tickUpper: pos.tickUpper,
            liquidityDelta: -int256(uint256(pos.liquidity)),
            salt: bytes32(0)
        });

        (BalanceDelta delta,) = poolManager.modifyLiquidity(pos.key, params, bytes(""));
        _takePositiveDeltas(pos.key, delta);
        pos.liquidity = 0;
    }

    /// @dev Re-adds recalled capital as concentrated liquidity.
    function _handleRecallFromYield(bytes calldata data) internal returns (bytes memory) {
        (, bytes32 positionId, uint256 recalled) = abi.decode(data, (Action, bytes32, uint256));
        TrackedPosition storage pos = positions[positionId];

        int256 liquidityDelta = int256(recalled);

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: pos.tickLower,
            tickUpper: pos.tickUpper,
            liquidityDelta: liquidityDelta,
            salt: bytes32(0)
        });

        (BalanceDelta delta,) = poolManager.modifyLiquidity(pos.key, params, abi.encode(true));
        _settleDeltas(pos.key, delta);

        return abi.encode(uint128(uint256(liquidityDelta)));
    }

    // -------------------------------------------------------------------------
    // Token settlement helpers
    // -------------------------------------------------------------------------

    /// @dev Transfers tokens to PoolManager to cover negative (owed) balance deltas.
    function _settleDeltas(PoolKey memory key, BalanceDelta delta) internal {
        int128 d0 = delta.amount0();
        int128 d1 = delta.amount1();

        if (d0 < 0) {
            uint256 owed = uint256(uint128(-d0));
            IERC20(Currency.unwrap(key.currency0)).safeTransfer(address(poolManager), owed);
            poolManager.settle();
        }
        if (d1 < 0) {
            uint256 owed = uint256(uint128(-d1));
            IERC20(Currency.unwrap(key.currency1)).safeTransfer(address(poolManager), owed);
            poolManager.settle();
        }
    }

    /// @dev Calls poolManager.take() to pull tokens owed to this contract (positive deltas).
    function _takePositiveDeltas(PoolKey memory key, BalanceDelta delta) internal {
        if (delta.amount0() > 0) {
            poolManager.take(key.currency0, address(this), uint128(delta.amount0()));
        }
        if (delta.amount1() > 0) {
            poolManager.take(key.currency1, address(this), uint128(delta.amount1()));
        }
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /// @notice Sets the Reactive Smart Contract authorised to trigger routing.
    ///         Should be called once after the RSC is deployed on Reactive Network.
    function setReactiveContract(address rsc) external onlyOwner {
        reactiveContract = rsc;
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /// @notice Returns all position IDs owned by `account`
    function getOwnerPositions(address account) external view returns (bytes32[] memory) {
        return ownerPositions[account];
    }

    /// @notice Returns the full on-chain state of a position
    function getPosition(bytes32 positionId)
        external
        view
        returns (TrackedPosition memory)
    {
        return positions[positionId];
    }

    /// @notice Computes the deterministic position ID for a given owner + pool + range
    function computePositionId(
        address owner_,
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper
    ) external pure returns (bytes32) {
        return _positionId(owner_, key.toId(), tickLower, tickUpper);
    }

    // -------------------------------------------------------------------------
    // Internal pure helper
    // -------------------------------------------------------------------------

    function _positionId(address owner_, PoolId pid, int24 tickLower, int24 tickUpper)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(owner_, pid, tickLower, tickUpper));
    }
}
