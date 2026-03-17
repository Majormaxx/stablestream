// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

import {StableStreamHook} from "../src/StableStreamHook.sol";
import {YieldRouter} from "../src/YieldRouter.sol";
import {RangeCalculator} from "../src/libraries/RangeCalculator.sol";
import {YieldAccounting} from "../src/libraries/YieldAccounting.sol";


/// @notice Minimal ERC-20 mock for USDC in tests
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/// @notice Stub yield adapter used in unit tests (no real Aave/Compound needed)
contract MockYieldSource {
    address public immutable _asset;
    uint256 private _apy; // in bps
    mapping(address => uint256) private _balances;

    constructor(address asset_, uint256 initialAPY) {
        _asset = asset_;
        _apy = initialAPY;
    }

    function setAPY(uint256 apy) external { _apy = apy; }

    function deposit(uint256 amount) external returns (uint256) {
        MockERC20(_asset).transferFrom(msg.sender, address(this), amount);
        _balances[msg.sender] += amount;
        return amount;
    }

    function withdraw(uint256 amount) external returns (uint256) {
        _balances[msg.sender] -= amount;
        MockERC20(_asset).transfer(msg.sender, amount);
        return amount;
    }

    function withdrawAll() external returns (uint256) {
        uint256 bal = _balances[msg.sender];
        if (bal == 0) return 0;
        _balances[msg.sender] = 0;
        MockERC20(_asset).transfer(msg.sender, bal);
        return bal;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function currentAPY() external view returns (uint256) { return _apy; }
    function asset() external view returns (address) { return _asset; }
    function maxDeposit() external pure returns (uint256) { return type(uint256).max; }
}

/// @title StableStreamHookTest
/// @notice Unit tests for StableStreamHook and supporting contracts.
///         Uses a local PoolManager fork (no RPC required for unit tests).
///         Fork tests for live Aave/Compound integration are in Integration.t.sol.
contract StableStreamHookTest is Test {
    using PoolIdLibrary for PoolKey;
    using YieldAccounting for YieldAccounting.YieldState;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    PoolManager internal poolManager;
    MockERC20 internal usdc;
    MockERC20 internal usdt;
    MockYieldSource internal aaveMock;
    MockYieldSource internal compoundMock;
    YieldRouter internal yieldRouter;
    StableStreamHook internal hook;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal rsc = makeAddr("rsc");
    address internal owner = makeAddr("owner");

    PoolKey internal poolKey;
    PoolId internal pid;

    // Typical stablecoin tick spacing (0.01% fee tier → tickSpacing 1)
    int24 constant TICK_SPACING = 1;
    // A tight range around the peg — 5 ticks each side of 0
    int24 constant TICK_LOWER = -5;
    int24 constant TICK_UPPER = 5;

    uint256 constant INITIAL_USDC = 100_000e6; // 100k USDC

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        // Deploy PoolManager (v4-core constructor takes initialOwner address)
        poolManager = new PoolManager(owner);

        // Deploy mock tokens (USDC = 6 decimals)
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether USD", "USDT", 6);

        // Sort currencies (v4 requires currency0 < currency1 by address)
        (address t0, address t1) = address(usdc) < address(usdt)
            ? (address(usdc), address(usdt))
            : (address(usdt), address(usdc));

        // Deploy mock yield sources
        aaveMock = new MockYieldSource(address(usdc), 320); // 3.20% APY
        compoundMock = new MockYieldSource(address(usdc), 280); // 2.80% APY

        // Deploy YieldRouter
        yieldRouter = new YieldRouter(address(usdc), owner);
        vm.startPrank(owner);
        yieldRouter.registerSource(address(aaveMock));
        yieldRouter.registerSource(address(compoundMock));
        vm.stopPrank();

        // Deploy hook (address must have the right flags; in tests we use deployCodeTo)
        // For simplicity we deploy and then use vm.etch to place at a compliant address.
        // In a real deploy you'd mine a vanity address.
        hook = new StableStreamHook(
            IPoolManager(address(poolManager)),
            yieldRouter,
            address(usdc),
            owner
        );

        vm.prank(owner);
        hook.setReactiveContract(rsc);

        // Set authorized caller on router
        vm.prank(owner);
        yieldRouter.setAuthorizedCaller(address(hook));

        // Build pool key (1 bps fee, tick spacing 1 — typical for stablecoins)
        poolKey = PoolKey({
            currency0: Currency.wrap(t0),
            currency1: Currency.wrap(t1),
            fee: 100,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        pid = poolKey.toId();

        // Mint USDC to test users
        usdc.mint(alice, INITIAL_USDC);
        usdc.mint(bob, INITIAL_USDC);
        usdt.mint(alice, INITIAL_USDC);
    }

    // -------------------------------------------------------------------------
    // RangeCalculator tests
    // -------------------------------------------------------------------------

    function test_isInRange_returnsTrue_whenTickInsideBounds() public pure {
        assertTrue(RangeCalculator.isInRange(0, TICK_LOWER, TICK_UPPER));
        assertTrue(RangeCalculator.isInRange(-5, TICK_LOWER, TICK_UPPER)); // at lower bound
        assertTrue(RangeCalculator.isInRange(4, TICK_LOWER, TICK_UPPER));  // below upper bound
    }

    function test_isInRange_returnsFalse_whenTickAtUpperBound() public pure {
        // v4 convention: tickUpper is exclusive
        assertFalse(RangeCalculator.isInRange(5, TICK_LOWER, TICK_UPPER));
    }

    function test_isInRange_returnsFalse_whenTickOutsideBounds() public pure {
        assertFalse(RangeCalculator.isInRange(-6, TICK_LOWER, TICK_UPPER));
        assertFalse(RangeCalculator.isInRange(10, TICK_LOWER, TICK_UPPER));
    }

    function test_crossedOutOfRange_detectsLowerExit() public pure {
        // tick moved from 0 (in range) to -6 (below lower bound)
        assertTrue(RangeCalculator.crossedOutOfRange(0, -6, TICK_LOWER, TICK_UPPER));
    }

    function test_crossedOutOfRange_detectsUpperExit() public pure {
        // tick moved from 3 (in range) to 7 (above upper bound)
        assertTrue(RangeCalculator.crossedOutOfRange(3, 7, TICK_LOWER, TICK_UPPER));
    }

    function test_crossedOutOfRange_returnsFalse_whenAlreadyOutside() public pure {
        assertFalse(RangeCalculator.crossedOutOfRange(-10, -8, TICK_LOWER, TICK_UPPER));
    }

    function test_crossedIntoRange_detectsEntry() public pure {
        assertTrue(RangeCalculator.crossedIntoRange(-10, 0, TICK_LOWER, TICK_UPPER));
        assertTrue(RangeCalculator.crossedIntoRange(10, -5, TICK_LOWER, TICK_UPPER));
    }

    // -------------------------------------------------------------------------
    // YieldAccounting tests
    // -------------------------------------------------------------------------

    function test_yieldAccounting_recordDeposit_incrementsPrincipal() public {
        YieldAccounting.YieldState storage state;
        // Use a local mapping to get a storage ref in tests
        bytes32 slot = keccak256("test.slot");
        assembly { state.slot := slot }

        state.recordDeposit(50_000e6);
        assertEq(state.depositedPrincipal, 50_000e6);
        assertGt(state.lastRouteTimestamp, 0);
    }

    function test_yieldAccounting_grossYield_computesCorrectly() public pure {
        YieldAccounting.YieldState memory state;
        state.depositedPrincipal = 50_000e6;

        // 3% yield = 1,500 USDC
        uint256 currentBal = 51_500e6;
        assertEq(YieldAccounting.grossYield(state, currentBal), 1_500e6);
    }

    function test_yieldAccounting_grossYield_returnsZero_onNegativeReturn() public pure {
        YieldAccounting.YieldState memory state;
        state.depositedPrincipal = 50_000e6;
        // Balance below principal (slippage / rounding)
        assertEq(YieldAccounting.grossYield(state, 49_999e6), 0);
    }

    function test_yieldAccounting_recordWithdrawal_clearsState() public {
        YieldAccounting.YieldState storage state;
        bytes32 slot = keccak256("test.slot2");
        assembly { state.slot := slot }

        state.recordDeposit(50_000e6);
        // Withdraw with 500 USDC yield
        state.recordWithdrawal(50_500e6);

        assertEq(state.depositedPrincipal, 0);
        assertEq(state.harvestedYield, 500e6);
    }

    function test_yieldAccounting_canRoute_respectsCooldown() public {
        YieldAccounting.YieldState storage state;
        bytes32 slot = keccak256("test.slot3");
        assembly { state.slot := slot }

        state.recordDeposit(1e6); // sets lastRouteTimestamp = now

        // Immediately after deposit, cooldown is active
        assertFalse(state.canRoute(60));

        // After cooldown passes, routing is allowed
        vm.warp(block.timestamp + 61);
        assertTrue(state.canRoute(60));
    }

    // -------------------------------------------------------------------------
    // YieldRouter tests
    // -------------------------------------------------------------------------

    function test_yieldRouter_registerSource_addsSource() public view {
        assertEq(yieldRouter.sources(0), address(aaveMock));
        assertEq(yieldRouter.sources(1), address(compoundMock));
        assertEq(yieldRouter.sourceCount(), 2);
    }

    function test_yieldRouter_bestSource_pickHighestAPY() public view {
        // Aave at 320 bps > Compound at 280 bps
        address best = yieldRouter.bestSource(1e6);
        assertEq(best, address(aaveMock));
    }

    function test_yieldRouter_bestSource_switchesWhenAPYChanges() public {
        aaveMock.setAPY(100); // drop Aave to 1%
        address best = yieldRouter.bestSource(1e6);
        assertEq(best, address(compoundMock));
    }

    function test_yieldRouter_routeToBestSource_depositsToHighestAPY() public {
        vm.startPrank(address(hook));
        usdc.mint(address(hook), 10_000e6);
        usdc.approve(address(yieldRouter), 10_000e6);

        address chosen = yieldRouter.routeToBestSource(10_000e6);
        vm.stopPrank();

        assertEq(chosen, address(aaveMock));
        assertEq(aaveMock.balanceOf(address(yieldRouter)), 10_000e6);
    }

    function test_yieldRouter_recallFromSource_returnsTokens() public {
        // First deposit
        vm.startPrank(address(hook));
        usdc.mint(address(hook), 10_000e6);
        usdc.approve(address(yieldRouter), 10_000e6);
        yieldRouter.routeToBestSource(10_000e6);

        // Now recall
        uint256 hookBefore = usdc.balanceOf(address(hook));
        yieldRouter.recallFromSource(address(aaveMock), 5_000e6, address(hook));
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(hook)) - hookBefore, 5_000e6);
        assertEq(aaveMock.balanceOf(address(yieldRouter)), 5_000e6);
    }

    function test_yieldRouter_switchSource_movesAllFunds() public {
        vm.startPrank(address(hook));
        usdc.mint(address(hook), 20_000e6);
        usdc.approve(address(yieldRouter), 20_000e6);
        yieldRouter.routeToSource(address(aaveMock), 20_000e6);

        // Switch Aave → Compound
        yieldRouter.switchSource(address(aaveMock), address(compoundMock));
        vm.stopPrank();

        assertEq(aaveMock.balanceOf(address(yieldRouter)), 0);
        assertEq(compoundMock.balanceOf(address(yieldRouter)), 20_000e6);
    }

    function test_yieldRouter_emergencyWithdrawAll_drainsAllSources() public {
        vm.startPrank(address(hook));
        usdc.mint(address(hook), 30_000e6);
        usdc.approve(address(yieldRouter), 30_000e6);
        yieldRouter.routeToSource(address(aaveMock), 15_000e6);
        yieldRouter.routeToSource(address(compoundMock), 15_000e6);
        vm.stopPrank();

        address emergencyAddr = makeAddr("emergency");
        vm.prank(owner);
        yieldRouter.emergencyWithdrawAll(emergencyAddr);

        assertEq(usdc.balanceOf(emergencyAddr), 30_000e6);
        assertEq(yieldRouter.totalBalance(), 0);
    }

    // -------------------------------------------------------------------------
    // Hook permission tests
    // -------------------------------------------------------------------------

    function test_getHookPermissions_setsCorrectFlags() public view {
        Hooks.Permissions memory perms = hook.getHookPermissions();

        assertTrue(perms.afterAddLiquidity);
        assertTrue(perms.beforeRemoveLiquidity);
        assertTrue(perms.beforeSwap);
        assertTrue(perms.afterSwap);

        assertFalse(perms.beforeInitialize);
        assertFalse(perms.afterInitialize);
        assertFalse(perms.beforeAddLiquidity);
        assertFalse(perms.afterRemoveLiquidity);
    }

    // -------------------------------------------------------------------------
    // Access control tests
    // -------------------------------------------------------------------------

    function test_routeToYield_revertsForUnauthorizedCaller() public {
        bytes32 fakeId = keccak256("fake");
        vm.expectRevert(StableStreamHook.UnauthorizedRoutingCaller.selector);
        vm.prank(alice);
        hook.routeToYield(fakeId);
    }

    function test_recallFromYield_revertsForUnauthorizedCaller() public {
        bytes32 fakeId = keccak256("fake");
        vm.expectRevert(StableStreamHook.UnauthorizedRoutingCaller.selector);
        vm.prank(alice);
        hook.recallFromYield(fakeId);
    }

    function test_routeToYield_revertsForNonexistentPosition() public {
        bytes32 fakeId = keccak256("nonexistent");
        vm.expectRevert(abi.encodeWithSelector(StableStreamHook.PositionNotFound.selector, fakeId));
        vm.prank(rsc);
        hook.routeToYield(fakeId);
    }

    // -------------------------------------------------------------------------
    // Helper
    // -------------------------------------------------------------------------

    function _sqrtPriceAtTick(int24 tick) internal pure returns (uint160) {
        return TickMath.getSqrtPriceAtTick(tick);
    }
}
