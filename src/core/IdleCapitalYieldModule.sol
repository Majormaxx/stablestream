// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";

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

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {YieldRouter} from "./YieldRouter.sol";
import {RangeCalculator} from "./libraries/RangeCalculator.sol";
import {YieldAccounting} from "./libraries/YieldAccounting.sol";
import {TransientStorage} from "./libraries/TransientStorage.sol";
import {DynamicFeeModule} from "./libraries/DynamicFeeModule.sol";

/// @title IdleCapitalYieldModule
/// @notice Reusable abstract base contract for Uniswap v4 hooks that automatically
///         route idle concentrated-liquidity capital to external yield sources.
///
///         Any hook contract inherits this module, deploys a YieldRouter + adapters,
///         and gets automatic out-of-range yield routing with no off-chain infrastructure.
///
/// @dev    Feature summary:
///           - Detects out-of-range positions via afterSwap tick scans
///           - Emits events for Reactive Network RSC to trigger routeToYield/recallFromYield
///           - Routes idle capital to the highest-yielding registered source
///           - JIT recalls capital when a swap re-enters position range
///           - Dynamic fee scaling based on yield utilisation ratio
///
///         To integrate: inherit, call the constructor, and optionally override
///         _onPositionOpened / _onPositionClosed for custom lifecycle handling
///         (NFT minting, notifications, etc).
abstract contract IdleCapitalYieldModule is IHooks, SafeCallback, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using YieldAccounting for YieldAccounting.YieldState;

    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    enum Action {
        DEPOSIT,
        WITHDRAW,
        ROUTE_TO_YIELD,
        RECALL_FROM_YIELD
    }

    struct TrackedPosition {
        address owner;
        address asset;
        PoolId poolId;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 yieldDeposited;
        address activeYieldSource;
        YieldAccounting.YieldState yieldState;
        bool closed;
        PoolKey key;
    }

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant ROUTE_COOLDOWN = 60 seconds;

    bytes32 private constant PENDING_RECALL_PREFIX =
        keccak256("StableStream.pendingRecall.v1");

    // -------------------------------------------------------------------------
    // Immutable state
    // -------------------------------------------------------------------------

    YieldRouter public immutable yieldRouter;
    IERC20 public immutable usdc;

    // -------------------------------------------------------------------------
    // Mutable state
    // -------------------------------------------------------------------------

    mapping(bytes32 positionId => TrackedPosition) public positions;
    mapping(address owner => bytes32[]) public ownerPositions;
    mapping(PoolId poolId => bytes32[]) private _poolPositionIds;
    mapping(PoolId poolId => int24) private _prevTicks;
    mapping(PoolId poolId => uint256) public poolTotalCapital;
    mapping(PoolId poolId => uint256) public poolYieldCapital;
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
    error CapitalInYield(bytes32 positionId);

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event PositionOpened(
        bytes32 indexed positionId,
        address indexed owner,
        PoolId indexed poolId,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    );

    event PositionLeftRange(bytes32 indexed positionId, int24 newTick);
    event PositionEnteredRange(bytes32 indexed positionId, int24 currentTick);

    event CapitalRouted(
        bytes32 indexed positionId,
        address indexed yieldSource,
        uint256 amount
    );

    event CapitalRecalled(
        bytes32 indexed positionId,
        address indexed yieldSource,
        uint256 received,
        uint128 newLiquidity
    );

    event PositionExited(
        bytes32 indexed positionId,
        address indexed owner,
        uint256 capitalReturned,
        uint256 yieldEarned
    );

    // -------------------------------------------------------------------------
    // Virtual lifecycle hooks (product-specific extensions)
    // -------------------------------------------------------------------------

    function _onPositionOpened(bytes32 positionId, address owner) internal virtual {}

    function _onPositionClosed(bytes32 positionId) internal virtual {}

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

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

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -------------------------------------------------------------------------
    // IHooks — callbacks
    // -------------------------------------------------------------------------

    function beforeInitialize(address, PoolKey calldata, uint160)
        external
        pure
        returns (bytes4)
    {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24)
        external
        pure
        returns (bytes4)
    {
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4, BalanceDelta) {
        if (hookData.length == 32) {
            bool internal_ = abi.decode(hookData, (bool));
            if (internal_) {
                return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
            }
        }
        return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

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

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId pid = key.toId();

        uint24 lpFeeOverride = 0;
        if (LPFeeLibrary.isDynamicFee(key.fee)) {
            lpFeeOverride = DynamicFeeModule.computeFee(
                poolTotalCapital[pid],
                poolYieldCapital[pid]
            );
        }

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, lpFeeOverride);
    }

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

            if (!pos.closed) {
                if (pos.liquidity > 0) {
                    if (RangeCalculator.crossedOutOfRange(prevTick, newTick, pos.tickLower, pos.tickUpper)) {
                        emit PositionLeftRange(posId, newTick);
                    }
                } else if (pos.yieldDeposited > 0) {
                    bytes32 slot = TransientStorage.slotFor(PENDING_RECALL_PREFIX, posId);
                    if (!TransientStorage.tload(slot)) {
                        if (RangeCalculator.crossedIntoRange(prevTick, newTick, pos.tickLower, pos.tickUpper)) {
                            TransientStorage.tstore(slot, true);
                            emit PositionEnteredRange(posId, newTick);
                        }
                    }
                }
            }

            unchecked { ++i; }
        }

        return (IHooks.afterSwap.selector, 0);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.beforeDonate.selector;
    }

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

        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);

        bytes memory result = poolManager.unlock(
            abi.encode(Action.DEPOSIT, msg.sender, key, tickLower, tickUpper, usdcAmount, positionId)
        );
        uint128 liquidity = abi.decode(result, (uint128));

        _registerPosition(positionId, msg.sender, key, tickLower, tickUpper, liquidity, usdcAmount, address(usdc));
    }

    // -------------------------------------------------------------------------
    // User-facing: withdraw
    // -------------------------------------------------------------------------

    function withdraw(bytes32 positionId) external nonReentrant returns (uint256 returned) {
        TrackedPosition storage pos = positions[positionId];
        if (pos.owner == address(0)) revert PositionNotFound(positionId);
        if (pos.owner != msg.sender) revert NotOwnerOfPosition(positionId);
        if (pos.closed) revert PositionAlreadyClosed(positionId);

        uint256 beforeBal = usdc.balanceOf(address(this));

        if (pos.yieldDeposited > 0 && pos.activeYieldSource != address(0)) {
            uint256 recalled = yieldRouter.recallAllFromSource(pos.activeYieldSource, address(this));
            pos.yieldState.recordWithdrawal(recalled);
            _poolCapitalSnapshot(pos.poolId, pos.yieldDeposited, pos.yieldDeposited, false);
            pos.yieldDeposited = 0;
            pos.activeYieldSource = address(0);
        }

        if (pos.liquidity > 0) {
            Currency currency0 = pos.key.currency0;
            uint256 token0Before = currency0.isAddressZero()
                ? address(this).balance
                : IERC20(Currency.unwrap(currency0)).balanceOf(address(this));

            poolManager.unlock(abi.encode(Action.WITHDRAW, positionId));

            uint256 token0Received = (currency0.isAddressZero()
                ? address(this).balance
                : IERC20(Currency.unwrap(currency0)).balanceOf(address(this))) - token0Before;

            if (token0Received > 0) {
                if (currency0.isAddressZero()) {
                    (bool ok,) = payable(pos.owner).call{value: token0Received}("");
                    require(ok, "SSHook: ETH transfer failed");
                } else {
                    IERC20(Currency.unwrap(currency0)).safeTransfer(pos.owner, token0Received);
                }
            }
        }

        returned = usdc.balanceOf(address(this)) - beforeBal;
        uint256 yieldEarned = uint256(pos.yieldState.harvestedYield);

        pos.closed = true;
        _removeFromPoolPositionIds(pos.poolId, positionId);
        pos.liquidity = 0;
        TransientStorage.tstore(
            TransientStorage.slotFor(PENDING_RECALL_PREFIX, positionId),
            false
        );

        _poolCapitalSnapshot(pos.poolId, returned, 0, false);

        _onPositionClosed(positionId);

        if (returned > 0) {
            usdc.safeTransfer(msg.sender, returned);
        }

        emit PositionExited(positionId, msg.sender, returned, yieldEarned);
    }

    // -------------------------------------------------------------------------
    // RSC-triggered: routeToYield
    // -------------------------------------------------------------------------

    function routeToYield(bytes32 positionId) external nonReentrant {
        if (msg.sender != reactiveContract && msg.sender != owner()) {
            revert UnauthorizedRoutingCaller();
        }

        TrackedPosition storage pos = positions[positionId];
        if (pos.owner == address(0)) revert PositionNotFound(positionId);
        if (pos.closed) revert PositionAlreadyClosed(positionId);
        if (pos.liquidity == 0) revert ZeroAmount();
        if (pos.yieldDeposited > 0) revert PositionAlreadyRouted(positionId);

        (, int24 currentTick,,) = poolManager.getSlot0(pos.poolId);
        if (RangeCalculator.isInRange(currentTick, pos.tickLower, pos.tickUpper)) {
            revert PositionCurrentlyInRange(positionId);
        }

        if (!pos.yieldState.canRoute(ROUTE_COOLDOWN)) {
            revert RoutingCooldownActive(
                positionId,
                uint256(pos.yieldState.lastRouteTimestamp) + ROUTE_COOLDOWN
            );
        }

        Currency currency0 = pos.key.currency0;
        uint256 token0Before = currency0.isAddressZero()
            ? address(this).balance
            : IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 beforeBal = usdc.balanceOf(address(this));

        poolManager.unlock(abi.encode(Action.ROUTE_TO_YIELD, positionId));

        uint256 recovered = usdc.balanceOf(address(this)) - beforeBal;
        uint256 token0Received = (currency0.isAddressZero()
            ? address(this).balance
            : IERC20(Currency.unwrap(currency0)).balanceOf(address(this))) - token0Before;

        if (token0Received > 0) {
            if (currency0.isAddressZero()) {
                (bool ok,) = payable(pos.owner).call{value: token0Received}("");
                require(ok, "SSHook: ETH transfer failed");
            } else {
                IERC20(Currency.unwrap(currency0)).safeTransfer(pos.owner, token0Received);
            }
        }

        if (recovered == 0) {
            pos.closed = true;
            _removeFromPoolPositionIds(pos.poolId, positionId);
            _onPositionClosed(positionId);
            emit PositionExited(positionId, pos.owner, 0, 0);
            return;
        }

        usdc.forceApprove(address(yieldRouter), recovered);
        address chosen = yieldRouter.routeToBestSource(recovered);

        pos.yieldDeposited = recovered;
        pos.activeYieldSource = chosen;
        pos.liquidity = 0;
        pos.yieldState.recordDeposit(recovered);

        _poolCapitalSnapshot(pos.poolId, 0, recovered, true);

        emit CapitalRouted(positionId, chosen, recovered);
    }

    // -------------------------------------------------------------------------
    // RSC-triggered: recallFromYield
    // -------------------------------------------------------------------------

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

        uint256 beforeBal = usdc.balanceOf(address(this));
        yieldRouter.recallAllFromSource(prevSource, address(this));
        uint256 recalled = usdc.balanceOf(address(this)) - beforeBal;

        pos.yieldState.recordWithdrawal(recalled);
        pos.yieldDeposited = 0;
        pos.activeYieldSource = address(0);

        TransientStorage.tstore(
            TransientStorage.slotFor(PENDING_RECALL_PREFIX, positionId),
            false
        );

        _poolCapitalSnapshot(pos.poolId, 0, prevYieldDeposited, false);

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

    function _handleDeposit(bytes calldata data) internal returns (bytes memory) {
        (
            ,
            address depositor,
            PoolKey memory key,
            int24 tickLower,
            int24 tickUpper,
            uint256 usdcAmount,
        ) = abi.decode(data, (Action, address, PoolKey, int24, int24, uint256, bytes32));

        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, key.toId());
        uint160 sqrtRatioAX96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtPriceAtTick(tickUpper);

        uint128 liq;
        if (sqrtPriceX96 >= sqrtRatioBX96) {
            liq = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, usdcAmount);
        } else if (sqrtPriceX96 > sqrtRatioAX96) {
            liq = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtPriceX96, usdcAmount);
        } else {
            revert("ICYM: price below range, deposit ETH or choose a higher tick range");
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

        (depositor);

        return abi.encode(liq);
    }

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

    function _handleRecallFromYield(bytes calldata data) internal returns (bytes memory) {
        (, bytes32 positionId, uint256 recalled) = abi.decode(data, (Action, bytes32, uint256));
        TrackedPosition storage pos = positions[positionId];

        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, pos.key.toId());
        uint160 sqrtRatioAX96 = TickMath.getSqrtPriceAtTick(pos.tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtPriceAtTick(pos.tickUpper);

        uint128 liq;
        if (sqrtPriceX96 >= sqrtRatioBX96) {
            liq = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, recalled);
        } else if (sqrtPriceX96 > sqrtRatioAX96) {
            liq = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtPriceX96, recalled);
        } else {
            revert("ICYM: price below range on recall, withdraw instead");
        }

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: pos.tickLower,
            tickUpper: pos.tickUpper,
            liquidityDelta: int256(uint256(liq)),
            salt: bytes32(0)
        });

        (BalanceDelta delta,) = poolManager.modifyLiquidity(pos.key, params, abi.encode(true));
        _settleDeltas(pos.key, delta);

        return abi.encode(liq);
    }

    // -------------------------------------------------------------------------
    // Token settlement helpers
    // -------------------------------------------------------------------------

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

    function _settleCurrency(Currency currency, uint256 amount) internal {
        if (currency.isAddressZero()) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            IERC20(Currency.unwrap(currency)).safeTransfer(address(poolManager), amount);
            poolManager.settle();
        }
    }

    function _takePositiveDeltas(PoolKey memory key, BalanceDelta delta) internal {
        if (delta.amount0() > 0) {
            poolManager.take(key.currency0, address(this), uint128(delta.amount0()));
        }
        if (delta.amount1() > 0) {
            poolManager.take(key.currency1, address(this), uint128(delta.amount1()));
        }
    }

    // -------------------------------------------------------------------------
    // Position registration helpers
    // -------------------------------------------------------------------------

    function _registerPosition(
        bytes32 positionId,
        address owner,
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 capitalAmount,
        address asset
    ) internal {
        TrackedPosition storage pos = positions[positionId];
        pos.owner = owner;
        pos.asset = asset;
        pos.poolId = key.toId();
        pos.tickLower = tickLower;
        pos.tickUpper = tickUpper;
        pos.liquidity = liquidity;
        pos.key = key;

        ownerPositions[owner].push(positionId);
        _poolPositionIds[key.toId()].push(positionId);
        _poolCapitalSnapshot(key.toId(), capitalAmount, 0, true);

        emit PositionOpened(positionId, owner, key.toId(), tickLower, tickUpper, liquidity);
        _onPositionOpened(positionId, owner);
    }

    // -------------------------------------------------------------------------
    // Capital accounting helper (DynamicFeeModule)
    // -------------------------------------------------------------------------

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

    function _removeFromPoolPositionIds(PoolId pid, bytes32 positionId) internal {
        bytes32[] storage arr = _poolPositionIds[pid];
        uint256 len = arr.length;
        for (uint256 i = 0; i < len; ) {
            if (arr[i] == positionId) {
                arr[i] = arr[len - 1];
                arr.pop();
                break;
            }
            unchecked { ++i; }
        }
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    function setReactiveContract(address rsc) external onlyOwner {
        reactiveContract = rsc;
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    function getOwnerPositions(address account) external view returns (bytes32[] memory) {
        return ownerPositions[account];
    }

    function getPosition(bytes32 positionId)
        external
        view
        returns (TrackedPosition memory)
    {
        return positions[positionId];
    }

    function computePositionId(
        address owner_,
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper
    ) external pure returns (bytes32) {
        return _positionId(owner_, key.toId(), tickLower, tickUpper);
    }

    function isPendingRecall(bytes32 positionId) external view returns (bool) {
        return TransientStorage.tload(
            TransientStorage.slotFor(PENDING_RECALL_PREFIX, positionId)
        );
    }

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
