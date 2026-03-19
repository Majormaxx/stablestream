// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

import {StableStreamHook} from "../src/StableStreamHook.sol";
import {YieldRouter} from "../src/YieldRouter.sol";

/// @notice Minimal mintable ERC-20 for multi-token tests
contract MockToken {
    string public name;
    string public symbol;
    uint8  public decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _dec) {
        name = _name; symbol = _symbol; decimals = _dec;
    }
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    function approve(address sp, uint256 amt) external returns (bool) {
        allowance[msg.sender][sp] = amt; return true;
    }
    function transfer(address to, uint256 amt) external returns (bool) {
        balanceOf[msg.sender] -= amt; balanceOf[to] += amt; return true;
    }
    function transferFrom(address fr, address to, uint256 amt) external returns (bool) {
        if (allowance[fr][msg.sender] != type(uint256).max)
            allowance[fr][msg.sender] -= amt;
        balanceOf[fr] -= amt; balanceOf[to] += amt; return true;
    }
}

/// @title MultiTokenTest
/// @notice Tests for multi-stablecoin support in StableStreamHook.
///         Verifies whitelisting, tokenRouter mappings, and TrackedPosition.asset field.
contract MultiTokenTest is Test {
    PoolManager internal poolManager;
    MockToken   internal usdc;
    MockToken   internal usdt;
    MockToken   internal usde;
    YieldRouter internal usdcRouter;
    YieldRouter internal usdtRouter;
    StableStreamHook internal hook;

    address internal owner   = makeAddr("owner");
    address internal alice   = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        vm.startPrank(owner);
        poolManager = new PoolManager(owner);
        usdc  = new MockToken("USD Coin",     "USDC", 6);
        usdt  = new MockToken("Tether USD",   "USDT", 6);
        usde  = new MockToken("USD Ethena",   "USDE", 18);
        usdcRouter = new YieldRouter(address(usdc), owner);
        usdtRouter = new YieldRouter(address(usdt), owner);
        hook = new StableStreamHook(
            IPoolManager(address(poolManager)),
            usdcRouter,
            address(usdc),
            owner
        );
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // whitelistStablecoin()
    // -------------------------------------------------------------------------

    /// @notice whitelistStablecoin sets the mapping entries.
    function test_whitelistStablecoin_setsMapping() public {
        vm.prank(owner);
        hook.whitelistStablecoin(address(usdt), address(usdtRouter));

        assertTrue(hook.whitelistedStables(address(usdt)),       "USDT must be whitelisted");
        assertEq(hook.tokenRouters(address(usdt)), address(usdtRouter), "router must match");
    }

    /// @notice whitelistStablecoin is owner-only.
    function test_whitelistStablecoin_onlyOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        hook.whitelistStablecoin(address(usdt), address(usdtRouter));
    }

    /// @notice Multiple stablecoins can be whitelisted independently.
    function test_whitelistStablecoin_multipleTokensAreIndependent() public {
        vm.startPrank(owner);
        hook.whitelistStablecoin(address(usdt), address(usdtRouter));
        hook.whitelistStablecoin(address(usde), address(usdtRouter)); // reuse router for test
        vm.stopPrank();

        assertTrue(hook.whitelistedStables(address(usdt)), "USDT whitelisted");
        assertTrue(hook.whitelistedStables(address(usde)), "USDE whitelisted");
        assertFalse(hook.whitelistedStables(makeAddr("random")), "random not whitelisted");
    }

    /// @notice USDC is pre-whitelisted in constructor.
    function test_usdc_preWhitelistedInConstructor() public view {
        assertTrue(hook.whitelistedStables(address(usdc)), "USDC pre-whitelisted");
        assertEq(hook.tokenRouters(address(usdc)), address(usdcRouter), "USDC router set");
    }

    // -------------------------------------------------------------------------
    // tokenRouter mapping
    // -------------------------------------------------------------------------

    /// @notice Updating a whitelisted token's router works correctly.
    function test_tokenRouter_canBeUpdated() public {
        vm.startPrank(owner);
        hook.whitelistStablecoin(address(usdt), address(usdtRouter));
        // Override with a different router address
        YieldRouter newRouter = new YieldRouter(address(usdt), owner);
        hook.whitelistStablecoin(address(usdt), address(newRouter));
        vm.stopPrank();

        assertEq(hook.tokenRouters(address(usdt)), address(newRouter), "router should be updated");
    }

    /// @notice tokenRouters returns address(0) for non-whitelisted tokens.
    function test_tokenRouter_returnsZeroForUnknownToken() public {
        address unknown = makeAddr("unknown");
        assertEq(hook.tokenRouters(unknown), address(0), "unknown token router is 0");
    }

    // -------------------------------------------------------------------------
    // TrackedPosition.asset field
    // -------------------------------------------------------------------------

    /// @notice deposit() sets pos.asset to the primary stablecoin (USDC).
    ///         Full deposit integration requires address-mined hook, so we verify
    ///         the struct field exists by checking unregistered position returns zero.
    function test_trackedPosition_assetFieldExists() public view {
        bytes32 fakeId = keccak256("fake");
        StableStreamHook.TrackedPosition memory pos = hook.getPosition(fakeId);
        // Empty position has asset = address(0)
        assertEq(pos.asset, address(0), "unregistered position asset should be address(0)");
        assertEq(pos.owner, address(0), "unregistered position owner should be address(0)");
    }

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice whitelistStablecoin emits StablecoinWhitelisted event.
    function test_whitelistStablecoin_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit StablecoinWhitelisted(address(usdt), address(usdtRouter));
        hook.whitelistStablecoin(address(usdt), address(usdtRouter));
    }

    event StablecoinWhitelisted(address indexed token, address indexed router);

    // -------------------------------------------------------------------------
    // Security: whitelisting zero address
    // -------------------------------------------------------------------------

    /// @notice Whitelisting address(0) is permissible but semantically meaningless.
    ///         The hook does not revert — owner should avoid this in production.
    function test_whitelistStablecoin_zeroAddressIsPermitted() public {
        vm.prank(owner);
        // Should not revert — owner is responsible for sensible inputs
        hook.whitelistStablecoin(address(0), address(usdtRouter));
        assertTrue(hook.whitelistedStables(address(0)), "address(0) can be whitelisted");
    }
}
