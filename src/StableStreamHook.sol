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
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";

// OpenZeppelin (sourced from v4-core's submodule)
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// StableStream internals
import {YieldRouter} from "./YieldRouter.sol";
import {StableStreamNFT} from "./StableStreamNFT.sol";
import {RangeCalculator} from "./libraries/RangeCalculator.sol";
import {YieldAccounting} from "./libraries/YieldAccounting.sol";
import {TransientStorage} from "./libraries/TransientStorage.sol";
import {DynamicFeeModule} from "./DynamicFeeModule.sol";

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
///           3. beforeSwap()          — flags positions for JIT recall; returns dynamic fee
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
///         EIP-1153 Transient Storage
///         ──────────────────────────
///         The pendingRecall flag uses TSTORE/TLOAD (EIP-1153) instead of a
///         persistent mapping.  This saves ~22,000 gas per flag vs. cold SSTORE,
///         and the RSC's own deduplication logic (per-position cooldown) provides
///         the cross-transaction idempotency guarantee.
///
///         Dynamic Fees
///         ────────────
///         For pools initialized with LPFeeLibrary.DYNAMIC_FEE_FLAG, beforeSwap
///         returns a fee computed by DynamicFeeModule that scales with the fraction
///         of pool capital currently deployed to yield sources.
///
/// @custom:security-contact security@stablestream.xyz
contract StableStreamHook is IHooks, SafeCallback, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;
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
        /// @dev  Which stablecoin this position manages (multi-token support)
        address asset;
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

    /// @notice EIP-1153 transient storage prefix for pendingRecall flags.
    ///         Using a keccak256 prefix prevents slot collisions with other features.
    bytes32 private constant PENDING_RECALL_PREFIX =
        keccak256("StableStream.pendingRecall.v1");

    // -------------------------------------------------------------------------
    // Immutable state
    // -------------------------------------------------------------------------

    /// @notice YieldRouter that selects and interacts with yield adapters
    YieldRouter public immutable yieldRouter;

    /// @notice USDC ERC-20 token managed by this hook (primary stablecoin)
    IERC20 public immutable usdc;

    // -------------------------------------------------------------------------
    // Mutable state
    // -------------------------------------------------------------------------

    /// @notice Positions indexed by their unique ID
    mapping(bytes32 positionId => TrackedPosition) public positions;

    /// @notice All position IDs belonging to an owner (for enumeration)
    mapping(address owner => bytes32[]) public ownerPositions;

    /// @notice Per-pool ordered list of position IDs (for O(n) scans in callbacks)
    mapping(PoolId poolId => bytes32[]) private _poolPositionIds;

    /// @notice Last-known tick per pool, updated on every afterSwap
    mapping(PoolId poolId => int24) private _prevTicks;

    /// @notice Total USDC principal tracked per pool (in-pool + in-yield).
    ///         Used by DynamicFeeModule to compute the yield utilisation ratio.
    mapping(PoolId poolId => uint256) public poolTotalCapital;

    /// @notice USDC currently routed to external yield sources per pool.
    ///         Updated on routeToYield() and recallFromYield().
    mapping(PoolId poolId => uint256) public poolYieldCapital;

    /// @notice Whitelisted stablecoin tokens for multi-token support.
    ///         Only whitelisted tokens can open managed positions.
    mapping(address token => bool) public whitelistedStables;

    /// @notice Maps each whitelisted stablecoin to its dedicated YieldRouter.
    ///         Allows per-token yield strategy configuration.
    mapping(address token => address) public tokenRouters;

    /// @notice Address of the Reactive Smart Contract authorised to call routing functions
    address public reactiveContract;

    /// @notice Optional ERC-721 NFT contract for transferable position receipts.
    ///         If address(0), NFT minting/burning is skipped (backwards compatible).
    StableStreamNFT public nft;

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

    /// @notice Thrown in beforeRemoveLiquidity when a position's capital is in yield.
    ///         The LP must call withdraw() which handles the recall atomically.
    error CapitalInYield(bytes32 positionId);

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

    /// @notice Emitted when beforeSwap detects a swap will re-enter a position's range.
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

    /// @notice Emitted when a stablecoin is whitelisted for multi-token support
    event StablecoinWhitelisted(address indexed token, address indexed router);

    /// @notice Emitted when the NFT contract address is set
    event NFTContractSet(address indexed nftContract);

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

        // Pre-whitelist USDC as the default managed stablecoin
        whitelistedStables[_usdc] = true;
        tokenRouters[_usdc] = address(_yieldRouter);
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
            beforeSwap: true,              // flag positions for JIT recall; dynamic fee
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
            revert CapitalInYield(posId);
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
    ///       re-enter so the RSC can execute a JIT recall.
    ///
    ///       For dynamic-fee pools (LPFeeLibrary.DYNAMIC_FEE_FLAG), also returns the
    ///       fee computed by DynamicFeeModule based on current yield utilisation.
    ///
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
            bytes32 posId = poolIds[i];
            TrackedPosition storage pos = positions[posId];

            if (!pos.closed && pos.yieldDeposited > 0) {
                // Check transient storage: if already flagged this tx, skip re-emission
                bytes32 slot = TransientStorage.slotFor(PENDING_RECALL_PREFIX, posId);
                if (!TransientStorage.tload(slot)) {
                    bool couldEnter = RangeCalculator.swapCouldEnterRange(
                        currentTick,
                        params.zeroForOne,
                        params.sqrtPriceLimitX96,
                        pos.tickLower,
                        pos.tickUpper
                    );
                    if (couldEnter) {
                        TransientStorage.tstore(slot, true);
                        emit PositionEnteredRange(posId, currentTick);
                    }
                }
            }

            unchecked { ++i; }
        }

        // Dynamic fee: only returned for pools initialised with DYNAMIC_FEE_FLAG.
        // For static-fee pools this value is ignored by the PoolManager.
        uint24 lpFeeOverride = 0;
        if (LPFeeLibrary.isDynamicFee(key.fee)) {
            lpFeeOverride = DynamicFeeModule.computeFee(
                poolTotalCapital[pid],
                poolYieldCapital[pid]
            );
        }

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, lpFeeOverride);
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
            bytes32 posId = poolIds[i];
            TrackedPosition storage pos = positions[posId];

            if (!pos.closed && pos.liquidity > 0) {
                if (RangeCalculator.crossedOutOfRange(prevTick, newTick, pos.tickLower, pos.tickUpper)) {
                    emit PositionLeftRange(posId, newTick);
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
    ///         Mints an ERC-721 receipt NFT if the nft contract is configured.
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
        pos.asset = address(usdc);
        pos.poolId = key.toId();
        pos.tickLower = tickLower;
        pos.tickUpper = tickUpper;
        pos.liquidity = liquidity;
        pos.key = key;

        ownerPositions[msg.sender].push(positionId);
        _poolPositionIds[key.toId()].push(positionId);

        // Update pool capital tracking for dynamic fee module
        _poolCapitalSnapshot(key.toId(), usdcAmount, 0, true);

        // Mint ERC-721 receipt NFT if configured
        if (address(nft) != address(0)) {
            nft.mint(msg.sender, positionId);
        }

        emit PositionOpened(positionId, msg.sender, key.toId(), tickLower, tickUpper, liquidity);
    }

    // -------------------------------------------------------------------------
    // User-facing: withdraw
    // -------------------------------------------------------------------------

    /// @notice Closes a position and returns all capital (principal + yield) to the owner.
    ///         If capital is in a yield source, it is recalled first.
    ///         Burns the ERC-721 receipt NFT if configured.
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
            // Update pool capital tracking
            _poolCapitalSnapshot(pos.poolId, pos.yieldDeposited, pos.yieldDeposited, false);
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
        // Clear pending recall flag from transient storage
        TransientStorage.tstore(
            TransientStorage.slotFor(PENDING_RECALL_PREFIX, positionId),
            false
        );

        // Update total capital tracking on exit
        _poolCapitalSnapshot(pos.poolId, returned, 0, false);

        // Burn receipt NFT if configured
        if (address(nft) != address(0)) {
            nft.burn(positionId);
        }

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

        // Route USDC to best yield source via router
        usdc.forceApprove(address(yieldRouter), recovered);
        address chosen = yieldRouter.routeToBestSource(recovered);

        pos.yieldDeposited = recovered;
        pos.activeYieldSource = chosen;
        pos.liquidity = 0;
        pos.yieldState.recordDeposit(recovered);

        // Update pool capital tracking: capital stays in pool total, moves to yield bucket
        _poolCapitalSnapshot(pos.poolId, 0, recovered, true);

        emit CapitalRouted(positionId, chosen, recovered);
    }

    // -------------------------------------------------------------------------
    // RSC-triggered: recallFromYield
    // -------------------------------------------------------------------------

    /// @notice Withdraws capital from the yield source and re-adds it as active
    ///         liquidity in the pool (JIT re-entry).
    ///
    /// @dev    Only callable by the registered Reactive Smart Contract or the owner.
    ///         The RSC calls this after a PositionEnteredRange event.
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
        uint256 prevYieldDeposited = pos.yieldDeposited;

        // Recall all capital from yield source
        uint256 beforeBal = usdc.balanceOf(address(this));
        yieldRouter.recallAllFromSource(prevSource, address(this));
        uint256 recalled = usdc.balanceOf(address(this)) - beforeBal;

        pos.yieldState.recordWithdrawal(recalled);
        pos.yieldDeposited = 0;
        pos.activeYieldSource = address(0);

        // Clear pending recall flag from transient storage
        TransientStorage.tstore(
            TransientStorage.slotFor(PENDING_RECALL_PREFIX, positionId),
            false
        );

        // Update pool capital tracking: move capital out of yield bucket
        _poolCapitalSnapshot(pos.poolId, 0, prevYieldDeposited, false);

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

    /// @dev  Adds liquidity on behalf of the depositing LP.
    ///       Settles the USDC debt owed to PoolManager after modifyLiquidity.
    ///
    /// @dev  Liquidity delta calculation (USDC = token1, ETH = token0):
    ///
    ///       Three price-range cases for a token1-only deposit:
    ///
    ///       Case A — price ≥ tickUpper (range is entirely token1):
    ///         liq = getLiquidityForAmount1(sqrtRatioA, sqrtRatioB, usdcAmount)
    ///         The full [tickLower, tickUpper] band is priced in USDC. ✓
    ///
    ///       Case B — price in (tickLower, tickUpper) (range is mixed):
    ///         liq = getLiquidityForAmount1(sqrtRatioA, sqrtPrice, usdcAmount)
    ///         USDC covers the [tickLower, currentPrice] segment; ETH covers
    ///         [currentPrice, tickUpper].  Using the current price as upper bound
    ///         gives the correct L for our token1 contribution without requiring ETH.
    ///
    ///       Case C — price ≤ tickLower (range is entirely token0 / ETH):
    ///         The position holds no token1 at all; a USDC-only deposit is invalid
    ///         and reverts to protect the user's capital.
    ///
    ///       Bug in the previous implementation: the original code called
    ///       getLiquidityForAmounts(_, _, _, 0, usdcAmount).  In Case B this returns
    ///       min(liq_from_0_ETH, liq_from_USDC) = 0, then fell back to
    ///       getLiquidityForAmount1(sqrtRatioA, sqrtRatioB, usdcAmount) — the full-range
    ///       formula — which overstates liquidity and causes modifyLiquidity to request
    ///       more USDC than supplied.  In Case C the same fallback deposited USDC into
    ///       an ETH-only band, consuming funds with no correct position recorded.
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

        // Fetch current pool sqrt price and compute tick boundary sqrt prices.
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, key.toId());
        uint160 sqrtRatioAX96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtPriceAtTick(tickUpper);

        // USDC is token1.  Select the correct liquidity formula for each price case.
        uint128 liq;
        if (sqrtPriceX96 >= sqrtRatioBX96) {
            // Case A: price at or above tickUpper — range is entirely token1 (USDC).
            liq = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, usdcAmount);
        } else if (sqrtPriceX96 > sqrtRatioAX96) {
            // Case B: price is inside the range — USDC covers [tickLower, currentPrice].
            liq = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtPriceX96, usdcAmount);
        } else {
            // Case C: price at or below tickLower — range is entirely token0 (ETH).
            // A USDC-only deposit cannot provide any liquidity here; revert to protect funds.
            revert("SSHook: price below range, deposit ETH or choose a higher tick range");
        }

        int256 liquidityDelta = int256(uint256(liq));

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: liquidityDelta,
            salt: bytes32(0)
        });

        (BalanceDelta delta,) = poolManager.modifyLiquidity(key, params, abi.encode(true));
        _settleDeltas(key, delta);

        // Suppress unused variable warning for depositor — it's decoded for completeness
        (depositor);

        return abi.encode(liq);
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
    ///      Handles both native ETH (currency.isAddressZero()) and ERC-20 tokens correctly.
    ///
    ///      Native ETH pattern  : poolManager.settle{value: amount}()
    ///      ERC-20 pattern      : sync → safeTransfer → settle
    function _settleDeltas(PoolKey memory key, BalanceDelta delta) internal {
        int128 d0 = delta.amount0();
        int128 d1 = delta.amount1();

        if (d0 < 0) {
            uint256 owed = uint256(uint128(-d0));
            _settleCurrency(key.currency0, owed);
        }
        if (d1 < 0) {
            uint256 owed = uint256(uint128(-d1));
            _settleCurrency(key.currency1, owed);
        }
    }

    /// @dev Settles a single currency with the PoolManager, handling native ETH vs ERC-20.
    function _settleCurrency(Currency currency, uint256 amount) internal {
        if (currency.isAddressZero()) {
            // Native ETH: attach value directly to settle() call.
            poolManager.settle{value: amount}();
        } else {
            // ERC-20: sync balance snapshot, transfer tokens, then settle.
            poolManager.sync(currency);
            IERC20(Currency.unwrap(currency)).safeTransfer(address(poolManager), amount);
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
    // Capital accounting helper (DynamicFeeModule — WS3)
    // -------------------------------------------------------------------------

    /// @dev Updates the pool capital snapshot used by DynamicFeeModule.
    ///      Called on deposit, withdrawal, routeToYield, and recallFromYield.
    ///
    /// @param pid         Pool whose capital snapshot to update
    /// @param totalDelta  Change in total pool capital (0 if no change)
    /// @param yieldDelta  Change in yield-deployed capital (0 if no change)
    /// @param isDeposit   True for additions, false for removals
    function _poolCapitalSnapshot(
        PoolId pid,
        uint256 totalDelta,
        uint256 yieldDelta,
        bool isDeposit
    ) internal {
        if (isDeposit) {
            poolTotalCapital[pid] += totalDelta;
            poolYieldCapital[pid] += yieldDelta;
        } else {
            poolTotalCapital[pid] = poolTotalCapital[pid] > totalDelta
                ? poolTotalCapital[pid] - totalDelta
                : 0;
            poolYieldCapital[pid] = poolYieldCapital[pid] > yieldDelta
                ? poolYieldCapital[pid] - yieldDelta
                : 0;
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

    /// @notice Sets or updates the ERC-721 NFT contract for position receipts.
    ///         Pass address(0) to disable NFT minting/burning.
    function setNFT(StableStreamNFT _nft) external onlyOwner {
        nft = _nft;
        emit NFTContractSet(address(_nft));
    }

    /// @notice Whitelist a stablecoin token and assign its yield router.
    ///         Enables multi-token support beyond the primary USDC.
    ///
    /// @param token   ERC-20 stablecoin address (e.g. USDT, USDE, DAI)
    /// @param router  YieldRouter configured for this token
    function whitelistStablecoin(address token, address router) external onlyOwner {
        whitelistedStables[token] = true;
        tokenRouters[token] = router;
        emit StablecoinWhitelisted(token, router);
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

    /// @notice Returns whether a position has a pending JIT recall flag set this transaction.
    ///         Reads from transient storage — will return false in any new transaction.
    ///
    /// @param positionId  Position to check
    function isPendingRecall(bytes32 positionId) external view returns (bool) {
        return TransientStorage.tload(
            TransientStorage.slotFor(PENDING_RECALL_PREFIX, positionId)
        );
    }

    /// @notice Returns the dynamic fee that would be applied to a swap on `poolId`
    ///         given the current capital snapshot.  Useful for off-chain tooling.
    function getDynamicFee(PoolId poolId) external view returns (uint24) {
        return DynamicFeeModule.computeFee(poolTotalCapital[poolId], poolYieldCapital[poolId]);
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
