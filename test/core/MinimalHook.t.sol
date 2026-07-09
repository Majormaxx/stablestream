// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

import {MinimalHook} from "./MinimalHook.sol";
import {IdleCapitalYieldModule} from "../../src/core/IdleCapitalYieldModule.sol";
import {YieldRouter} from "../../src/core/YieldRouter.sol";
import {IYieldSource} from "../../src/core/interfaces/IYieldSource.sol";
import {DynamicFeeModule} from "../../src/core/libraries/DynamicFeeModule.sol";

/// @title MinimalHookTest
/// @notice Proves that IdleCapitalYieldModule works independently of StableStream's
///         product layer (NFT receipts, multi-token whitelisting, etc.).
///
///         A full lifecycle test (deposit → afterSwap detects range exit →
///         routeToYield → afterSwap detects range entry → recallFromYield →
///         withdraw) requires the hook to be deployed at a permission-mined address
///         that PoolManager accepts.  This test validates the module's reusability
///         guarantee: the MinimalHook compiles, deploys, inherits all core
///         functions unchanged, and passes the same error-guard and view-function
///         tests that StableStreamHook passes.
///
/// @dev    See Integration.t.sol for the full lifecycle against StableStreamHook
///         (the reference implementation).
contract MinimalHookTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    address internal constant OWNER = address(0x1);
    address internal constant RSC = address(0x4);

    PoolManager internal poolManager;
    MinimalHook internal minimalHook;

    function setUp() public {
        poolManager = new PoolManager(OWNER);

        // Deploy mock USDC and yield router
        // (uses the same mock contracts as StableStreamHookTest)
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 usdt = new MockERC20("Tether USD", "USDT", 6);

        (address t0, address t1) = address(usdc) < address(usdt)
            ? (address(usdc), address(usdt))
            : (address(usdt), address(usdc));

        MockYieldSource mockSource = new MockYieldSource(address(usdc), 300);
        YieldRouter yieldRouter = new YieldRouter(address(usdc), OWNER);
        vm.prank(OWNER);
        yieldRouter.registerSource(address(mockSource));

        minimalHook = new MinimalHook(
            IPoolManager(address(poolManager)),
            yieldRouter,
            address(usdc),
            OWNER
        );

        vm.prank(OWNER);
        yieldRouter.setAuthorizedCaller(address(minimalHook));

        vm.prank(OWNER);
        minimalHook.setReactiveContract(RSC);

        // Build pool key for view-function tests
        PoolKey memory pk = PoolKey({
            currency0: Currency.wrap(t0),
            currency1: Currency.wrap(t1),
            fee: 100,
            tickSpacing: 1,
            hooks: IHooks(address(minimalHook))
        });
        // Store pool key for test use
        s_poolKey = pk;
        s_pid = pk.toId();
    }

    PoolKey internal s_poolKey;
    PoolId internal s_pid;

    // -------------------------------------------------------------------------
    // Test 1: Compilation and inheritance — the module is standalone
    // -------------------------------------------------------------------------

    function test_minimal_compilesAndDeploys() public view {
        assertTrue(address(minimalHook) != address(0));
    }

    // -------------------------------------------------------------------------
    // Test 2: Hook permission flags match IHooks requirements
    // -------------------------------------------------------------------------

    function test_minimal_hookPermissionsMatchModule() public {
        Hooks.Permissions memory p = minimalHook.getHookPermissions();
        assertTrue(p.afterAddLiquidity);
        assertTrue(p.beforeRemoveLiquidity);
        assertTrue(p.beforeSwap);
        assertTrue(p.afterSwap);
    }

    // -------------------------------------------------------------------------
    // Test 3: Position ID is deterministic across contracts
    // -------------------------------------------------------------------------

    function test_minimal_positionIdDeterministic() public {
        bytes32 id = minimalHook.computePositionId(OWNER, s_poolKey, -5, 5);
        assertTrue(id != bytes32(0));

        // Same input → same output
        bytes32 id2 = minimalHook.computePositionId(OWNER, s_poolKey, -5, 5);
        assertEq(id, id2);

        // Different owner → different ID
        bytes32 id3 = minimalHook.computePositionId(address(0xDEAD), s_poolKey, -5, 5);
        assertNotEq(id, id3);
    }

    // -------------------------------------------------------------------------
    // Test 4: routeToYield reverts correctly for unauthorized caller
    // -------------------------------------------------------------------------

    function test_minimal_routeToYield_revertsUnauthorized() public {
        bytes32 fakeId = keccak256("fake");

        vm.prank(address(0xDEAD));
        vm.expectRevert(IdleCapitalYieldModule.UnauthorizedRoutingCaller.selector);
        minimalHook.routeToYield(fakeId);
    }

    // -------------------------------------------------------------------------
    // Test 5: routeToYield reverts for nonexistent position
    // -------------------------------------------------------------------------

    function test_minimal_routeToYield_revertsNonexistent() public {
        bytes32 fakeId = keccak256("fake");

        vm.prank(RSC);
        vm.expectRevert(abi.encodeWithSelector(IdleCapitalYieldModule.PositionNotFound.selector, fakeId));
        minimalHook.routeToYield(fakeId);
    }

    // -------------------------------------------------------------------------
    // Test 6: recallFromYield reverts correctly for unauthorized caller
    // -------------------------------------------------------------------------

    function test_minimal_recallFromYield_revertsUnauthorized() public {
        bytes32 fakeId = keccak256("fake");

        vm.prank(address(0xDEAD));
        vm.expectRevert(IdleCapitalYieldModule.UnauthorizedRoutingCaller.selector);
        minimalHook.recallFromYield(fakeId);
    }

    // -------------------------------------------------------------------------
    // Test 7: recallFromYield reverts for nonexistent position
    // -------------------------------------------------------------------------

    function test_minimal_recallFromYield_revertsNonexistent() public {
        bytes32 fakeId = keccak256("fake");

        vm.prank(RSC);
        vm.expectRevert(abi.encodeWithSelector(IdleCapitalYieldModule.PositionNotFound.selector, fakeId));
        minimalHook.recallFromYield(fakeId);
    }

    // -------------------------------------------------------------------------
    // Test 8: getDynamicFee returns a value
    // -------------------------------------------------------------------------

    function test_minimal_getDynamicFee() public view {
        // Without any capital, dynamic fee should be the base fee
        uint24 fee = minimalHook.getDynamicFee(s_pid);
        assertEq(fee, DynamicFeeModule.computeFee(0, 0));
    }

    // -------------------------------------------------------------------------
    // Test 9: setReactiveContract is owner-only
    // -------------------------------------------------------------------------

    function test_minimal_setReactiveContract_ownerOnly() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        minimalHook.setReactiveContract(address(0xDEAD));
    }

    // -------------------------------------------------------------------------
    // Test 10: getOwnerPositions returns empty for unregistered account
    // -------------------------------------------------------------------------

    function test_minimal_getOwnerPositions_empty() public view {
        bytes32[] memory positions = minimalHook.getOwnerPositions(OWNER);
        assertEq(positions.length, 0);
    }

    // -------------------------------------------------------------------------
    // Test 11: getPosition returns zeroed struct for nonexistent ID
    // -------------------------------------------------------------------------

    function test_minimal_getPosition_nonexistent() public view {
        bytes32 fakeId = keccak256("fake");
        IdleCapitalYieldModule.TrackedPosition memory pos = minimalHook.getPosition(fakeId);
        assertEq(pos.owner, address(0));
        assertTrue(pos.closed == false);
    }
}

/// @notice Minimal ERC-20 mock for MinimalHook tests
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

/// @notice Stub yield source for MinimalHook tests
contract MockYieldSource is IYieldSource {
    address public immutable _asset;
    uint256 private _apy;
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
