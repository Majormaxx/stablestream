// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CompoundV3Adapter} from "../src/adapters/CompoundV3Adapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

/// @notice Minimal ERC-20 with mint for tests.
contract MockERC20 {
    string  public name;
    string  public symbol;
    uint8   public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory n, string memory s, uint8 d) {
        name     = n;
        symbol   = s;
        decimals = d;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply   += amount;
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
        require(balanceOf[from] >= amount, "insufficient");
        balanceOf[from] -= amount;
        balanceOf[to]   += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/// @notice Mock Compound V3 Comet — tracks balances and returns configurable rates.
contract MockComet {
    MockERC20 public asset;
    mapping(address => uint256) public balanceOf;

    // Configurable rate (per second, 1e18 scaled)
    uint64 public supplyRatePerSec = 317_097_920; // ≈ 1% APY  (317097920 * 365 days ≈ 1e16 = 1%)

    // Configurable utilization
    uint256 public utilization = 0.8e18; // 80%

    constructor(address _asset) {
        asset = MockERC20(_asset);
    }

    function setSupplyRate(uint64 ratePerSec) external { supplyRatePerSec = ratePerSec; }
    function setUtilization(uint256 util) external { utilization = util; }

    function supply(address, uint256 amount) external {
        // Pull from caller
        asset.transferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
    }

    function withdraw(address, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        asset.transfer(msg.sender, amount);
    }

    function getSupplyRate(uint256) external view returns (uint64) {
        return supplyRatePerSec;
    }

    function getUtilization() external view returns (uint256) {
        return utilization;
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// @title CompoundV3AdapterTest
/// @notice Unit tests for CompoundV3Adapter — no fork, no external RPCs.
contract CompoundV3AdapterTest is Test {

    MockERC20          internal usdc;
    MockComet          internal comet;
    CompoundV3Adapter  internal adapter;

    address internal owner    = address(0xAA01);
    address internal caller   = address(0xBB02);
    address internal stranger = address(0xCC03);

    uint256 constant USDC_UNIT = 1e6; // 1 USDC

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        usdc    = new MockERC20("USD Coin", "USDC", 6);
        comet   = new MockComet(address(usdc));
        adapter = new CompoundV3Adapter(address(comet), address(usdc), owner);

        // Authorise `caller` as the caller (simulates YieldRouter)
        vm.prank(owner);
        adapter.setAuthorizedCaller(caller);

        // Fund `caller` with USDC and approve the adapter
        usdc.mint(caller, 10_000 * USDC_UNIT);
        vm.prank(caller);
        IERC20(address(usdc)).approve(address(adapter), type(uint256).max);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    function test_setAuthorizedCaller_onlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        adapter.setAuthorizedCaller(stranger);
    }

    function test_setAuthorizedCaller_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, false, address(adapter));
        emit CompoundV3Adapter.AuthorizedCallerUpdated(caller, stranger);
        adapter.setAuthorizedCaller(stranger);
    }

    function test_setAuthorizedCaller_updatesState() public {
        vm.prank(owner);
        adapter.setAuthorizedCaller(stranger);
        assertEq(adapter.authorizedCaller(), stranger);
    }

    // -------------------------------------------------------------------------
    // deposit()
    // -------------------------------------------------------------------------

    function test_deposit_basic() public {
        uint256 amount = 1_000 * USDC_UNIT;

        vm.prank(caller);
        uint256 shares = adapter.deposit(amount);

        assertEq(shares, amount, "shares == amount (1:1 Compound accounting)");
        assertEq(comet.balanceOf(address(adapter)), amount, "comet balance updated");
        assertEq(usdc.balanceOf(caller), 9_000 * USDC_UNIT, "usdc deducted from caller");
    }

    function test_deposit_unauthorized() public {
        vm.prank(stranger);
        vm.expectRevert(CompoundV3Adapter.Unauthorized.selector);
        adapter.deposit(1_000 * USDC_UNIT);
    }

    function test_deposit_zeroAmount() public {
        vm.prank(caller);
        vm.expectRevert(); // ZeroAmount or similar
        adapter.deposit(0);
    }

    function test_deposit_fuzz(uint64 amount) public {
        vm.assume(amount > 0 && amount <= 10_000 * USDC_UNIT);
        vm.prank(caller);
        uint256 shares = adapter.deposit(amount);
        assertEq(shares, amount);
    }

    // -------------------------------------------------------------------------
    // withdraw()
    // -------------------------------------------------------------------------

    function test_withdraw_basic() public {
        uint256 deposited = 2_000 * USDC_UNIT;
        vm.prank(caller);
        adapter.deposit(deposited);

        uint256 callerBefore = usdc.balanceOf(caller);

        vm.prank(caller);
        uint256 received = adapter.withdraw(deposited);

        assertEq(received, deposited, "received == deposited");
        assertEq(usdc.balanceOf(caller) - callerBefore, deposited, "caller balance restored");
        assertEq(comet.balanceOf(address(adapter)), 0, "comet balance zeroed");
    }

    function test_withdraw_unauthorized() public {
        vm.prank(caller);
        adapter.deposit(1_000 * USDC_UNIT);

        vm.prank(stranger);
        vm.expectRevert(CompoundV3Adapter.Unauthorized.selector);
        adapter.withdraw(1_000 * USDC_UNIT);
    }

    function test_withdraw_zeroAmount() public {
        vm.prank(caller);
        vm.expectRevert();
        adapter.withdraw(0);
    }

    function test_withdraw_partial() public {
        uint256 deposited = 3_000 * USDC_UNIT;
        vm.prank(caller);
        adapter.deposit(deposited);

        vm.prank(caller);
        adapter.withdraw(1_000 * USDC_UNIT);

        assertEq(comet.balanceOf(address(adapter)), 2_000 * USDC_UNIT, "remaining in comet");
    }

    // -------------------------------------------------------------------------
    // withdrawAll()
    // -------------------------------------------------------------------------

    function test_withdrawAll_basic() public {
        uint256 deposited = 500 * USDC_UNIT;
        vm.prank(caller);
        adapter.deposit(deposited);

        uint256 callerBefore = usdc.balanceOf(caller);

        vm.prank(caller);
        uint256 received = adapter.withdrawAll();

        assertEq(received, deposited, "all funds returned");
        assertEq(usdc.balanceOf(caller) - callerBefore, deposited);
        assertEq(comet.balanceOf(address(adapter)), 0);
    }

    function test_withdrawAll_whenEmpty_returnsZero() public {
        vm.prank(caller);
        uint256 received = adapter.withdrawAll();
        assertEq(received, 0, "nothing to withdraw");
    }

    function test_withdrawAll_unauthorized() public {
        vm.prank(caller);
        adapter.deposit(100 * USDC_UNIT);

        vm.prank(stranger);
        vm.expectRevert(CompoundV3Adapter.Unauthorized.selector);
        adapter.withdrawAll();
    }

    // -------------------------------------------------------------------------
    // balanceOf()
    // -------------------------------------------------------------------------

    function test_balanceOf_authorizedCaller() public {
        uint256 amount = 750 * USDC_UNIT;
        vm.prank(caller);
        adapter.deposit(amount);

        assertEq(adapter.balanceOf(caller), amount, "balanceOf returns comet balance for caller");
    }

    function test_balanceOf_adapterAddress() public {
        uint256 amount = 250 * USDC_UNIT;
        vm.prank(caller);
        adapter.deposit(amount);

        assertEq(adapter.balanceOf(address(adapter)), amount, "balanceOf(adapter) returns comet balance");
    }

    function test_balanceOf_stranger_returnsZero() public {
        vm.prank(caller);
        adapter.deposit(100 * USDC_UNIT);

        assertEq(adapter.balanceOf(stranger), 0, "stranger gets 0");
    }

    // -------------------------------------------------------------------------
    // currentAPY()
    // -------------------------------------------------------------------------

    function test_currentAPY_nonZero() public view {
        uint256 apy = adapter.currentAPY();
        assertGt(apy, 0, "APY should be positive with non-zero rate");
    }

    function test_currentAPY_math() public {
        // Set a known rate: 317_097_920 per second (≈ 1% APY)
        // APY_bps = ratePerSec * SECONDS_PER_YEAR * 10_000 / 1e18
        // = 317_097_920 * 31_536_000 * 10_000 / 1e18 ≈ 100 bps = 1%
        comet.setSupplyRate(317_097_920);
        uint256 apy = adapter.currentAPY();
        // Allow ±5 bps tolerance
        assertApproxEqAbs(apy, 100, 5, "APY ~= 1% (100 bps)");
    }

    function test_currentAPY_higherRate_higherAPY() public {
        comet.setSupplyRate(317_097_920);
        uint256 lowApy = adapter.currentAPY();

        comet.setSupplyRate(317_097_920 * 5); // 5x rate -> ~5% APY
        uint256 highApy = adapter.currentAPY();

        assertGt(highApy, lowApy, "higher rate => higher APY");
        assertApproxEqAbs(highApy, 500, 25, "5x rate ~= 5% APY");
    }

    function test_currentAPY_zeroRate() public {
        comet.setSupplyRate(0);
        assertEq(adapter.currentAPY(), 0, "zero rate -> zero APY");
    }

    // -------------------------------------------------------------------------
    // asset() and maxDeposit()
    // -------------------------------------------------------------------------

    function test_asset_returnsUSDC() public view {
        assertEq(adapter.asset(), address(usdc));
    }

    function test_maxDeposit_returnsMaxUint() public view {
        assertEq(adapter.maxDeposit(), type(uint256).max);
    }

    // -------------------------------------------------------------------------
    // comet() immutable
    // -------------------------------------------------------------------------

    function test_comet_immutable() public view {
        assertEq(address(adapter.comet()), address(comet));
    }

    // -------------------------------------------------------------------------
    // Round-trip: deposit -> withdraw
    // -------------------------------------------------------------------------

    function test_roundtrip_multipleDeposits() public {
        vm.startPrank(caller);
        adapter.deposit(1_000 * USDC_UNIT);
        adapter.deposit(2_000 * USDC_UNIT);
        vm.stopPrank();

        assertEq(comet.balanceOf(address(adapter)), 3_000 * USDC_UNIT, "total deposited");

        uint256 before = usdc.balanceOf(caller);
        vm.prank(caller);
        adapter.withdrawAll();
        assertEq(usdc.balanceOf(caller) - before, 3_000 * USDC_UNIT, "all funds back");
    }

    function test_roundtrip_depositWithdrawDeposit() public {
        vm.prank(caller);
        adapter.deposit(1_000 * USDC_UNIT);

        vm.prank(caller);
        adapter.withdraw(1_000 * USDC_UNIT);

        // Can deposit again after full withdrawal
        vm.prank(caller);
        adapter.deposit(500 * USDC_UNIT);

        assertEq(comet.balanceOf(address(adapter)), 500 * USDC_UNIT);
    }
}
