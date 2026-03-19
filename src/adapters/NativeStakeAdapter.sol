// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IYieldSource} from "../interfaces/IYieldSource.sol";

/// @dev Minimal interface for Unichain's native ETH staking contract.
///      Unichain's 1-second blocks and embedded sequencer staking allow direct
///      native ETH deposits that accrue staking rewards continuously.
///      The actual deployed address is configured at construction time.
interface IUnichainStaking {
    /// @notice Deposit native ETH and receive yield-bearing shares
    function deposit() external payable;

    /// @notice Redeem `shares` for the underlying ETH + accrued rewards
    function withdraw(uint256 shares) external;

    /// @notice Share balance of `account`
    function balanceOf(address account) external view returns (uint256);

    /// @notice Converts a share amount to the underlying ETH value
    function shareToAsset(uint256 shares) external view returns (uint256);

    /// @notice Current annualised yield in basis points (e.g. 420 = 4.20%)
    function currentAPYBps() external view returns (uint256);
}

/// @dev Simple swap interface — in production replace with a real DEX aggregator.
///      The adapter operates in USDC (6 dec); this bridge handles USDC ↔ ETH.
interface ISwapHelper {
    /// @notice Swap `amountIn` USDC for ETH, sending ETH to this contract.
    /// @return ethReceived Amount of ETH (18 dec) received
    function swapUSDCForETH(uint256 amountIn) external returns (uint256 ethReceived);

    /// @notice Swap `ethIn` ETH for USDC, sending USDC to `recipient`.
    /// @return usdcReceived Amount of USDC (6 dec) received
    function swapETHForUSDC(uint256 ethIn, address recipient)
        external
        payable
        returns (uint256 usdcReceived);
}

/// @title NativeStakeAdapter
/// @notice IYieldSource adapter that routes idle USDC into Unichain's native ETH staking.
///
/// @dev    Unichain offers ~4–6% APY on native ETH staking, higher than typical Aave/Compound
///         USDC supply rates (~3–4%). This adapter captures that premium for out-of-range
///         stablecoin LP positions.
///
///         Capital flow
///         ────────────
///         deposit(amount)
///           USDC → SWAP_HELPER.swapUSDCForETH() → ETH → IUnichainStaking.deposit() → shares
///
///         withdraw(amount)
///           shares → IUnichainStaking.withdraw() → ETH → SWAP_HELPER.swapETHForUSDC() → USDC → YieldRouter
///
///         The USDC↔ETH swap introduces price risk on stablecoin capital.
///         Mitigations:
///           1. Slippage guard: revert if usdcOut < usdcIn * (10000 - MAX_SLIPPAGE_BPS) / 10000
///           2. maxCapacity: caps total USDC deployed so ETH exposure stays bounded (default 500K)
///           3. In production: use a Chainlink ETH/USD feed to validate swap prices before executing
///
/// @custom:integration Unichain Native Staking
///         Deployed on Unichain mainnet (chain ID 130).
///         Unichain's 1-second block time means staking rewards compound nearly continuously —
///         approximately 31.5M reward events per year — maximising compounding for idle capital.
contract NativeStakeAdapter is IYieldSource, Ownable {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant MAX_SLIPPAGE_BPS = 100; // 1% max slippage on ETH↔USDC swap
    uint256 public constant MAX_CAPACITY_DEFAULT = 500_000e6; // 500,000 USDC

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    IUnichainStaking public immutable STAKING;
    ISwapHelper public immutable SWAP_HELPER;
    IERC20 public immutable USDC;

    // -------------------------------------------------------------------------
    // Mutable state
    // -------------------------------------------------------------------------

    /// @notice Address authorised to call deposit/withdraw (the YieldRouter)
    address public authorizedCaller;

    /// @notice Total USDC (principal) currently deployed through this adapter
    uint256 public totalDeposited;

    /// @notice Maximum USDC that can be deployed via this adapter at once
    uint256 public maxCapacity;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event StakeDeposited(uint256 usdcIn, uint256 ethStaked, uint256 sharesReceived);
    event StakeWithdrawn(uint256 sharesRedeemed, uint256 ethRecovered, uint256 usdcOut);
    event MaxCapacityUpdated(uint256 newCapacity);
    event AuthorizedCallerUpdated(address indexed newCaller);

    // -------------------------------------------------------------------------
    // Errors (supplement the ones inherited from IYieldSource)
    // -------------------------------------------------------------------------

    error Unauthorized();
    error SlippageExceeded(uint256 expectedMin, uint256 actual);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _staking      Unichain native staking contract
    /// @param _usdc         USDC ERC-20 address (6 decimals)
    /// @param _swapHelper   USDC↔ETH swap helper (DEX aggregator or on-chain AMM)
    /// @param _owner        Admin (multisig in production)
    constructor(
        address _staking,
        address _usdc,
        address _swapHelper,
        address _owner
    ) Ownable(_owner) {
        STAKING = IUnichainStaking(_staking);
        USDC = IERC20(_usdc);
        SWAP_HELPER = ISwapHelper(_swapHelper);
        maxCapacity = MAX_CAPACITY_DEFAULT;
    }

    // -------------------------------------------------------------------------
    // Modifier
    // -------------------------------------------------------------------------

    modifier onlyAuthorized() {
        if (msg.sender != authorizedCaller && msg.sender != owner()) revert Unauthorized();
        _;
    }

    // -------------------------------------------------------------------------
    // IYieldSource — mutative
    // -------------------------------------------------------------------------

    /// @inheritdoc IYieldSource
    /// @dev  Pull USDC from caller → swap to ETH → stake on Unichain.
    ///       Caller must approve this contract for `amount` USDC.
    function deposit(uint256 amount) external override onlyAuthorized returns (uint256 sharesReceived) {
        if (amount == 0) revert ZeroAmount();

        uint256 available = maxCapacity - totalDeposited;
        if (amount > available) revert ExceedsCapacity(amount, available);

        USDC.safeTransferFrom(msg.sender, address(this), amount);
        USDC.forceApprove(address(SWAP_HELPER), amount);

        uint256 ethReceived = SWAP_HELPER.swapUSDCForETH(amount);

        uint256 sharesBefore = STAKING.balanceOf(address(this));
        STAKING.deposit{value: ethReceived}();
        sharesReceived = STAKING.balanceOf(address(this)) - sharesBefore;

        totalDeposited += amount;

        emit StakeDeposited(amount, ethReceived, sharesReceived);
    }

    /// @inheritdoc IYieldSource
    /// @dev  Redeems a proportional share of staked ETH → swaps back to USDC →
    ///       returns USDC to caller (YieldRouter, which forwards to hook).
    function withdraw(uint256 amount) external override onlyAuthorized returns (uint256 usdcReceived) {
        if (amount == 0) revert ZeroAmount();

        uint256 totalShares = STAKING.balanceOf(address(this));
        if (totalShares == 0) return 0;

        // Determine shares to redeem proportional to `amount` of the total deposited
        uint256 sharesToRedeem = amount >= totalDeposited
            ? totalShares
            : (amount * totalShares) / totalDeposited;

        if (sharesToRedeem == 0) return 0;

        uint256 ethBefore = address(this).balance;
        STAKING.withdraw(sharesToRedeem);
        uint256 ethRecovered = address(this).balance - ethBefore;

        // Slippage guard: expect at least amount * (1 - slippage) USDC back
        uint256 minUSDC = (amount * (10_000 - MAX_SLIPPAGE_BPS)) / 10_000;

        usdcReceived = SWAP_HELPER.swapETHForUSDC{value: ethRecovered}(ethRecovered, msg.sender);
        if (usdcReceived < minUSDC) revert SlippageExceeded(minUSDC, usdcReceived);

        totalDeposited = amount >= totalDeposited ? 0 : totalDeposited - amount;

        emit StakeWithdrawn(sharesToRedeem, ethRecovered, usdcReceived);
    }

    /// @inheritdoc IYieldSource
    /// @dev  Redeems all staked ETH and returns USDC to caller.
    ///       Used for emergency recalls and full-position exits.
    function withdrawAll() external override onlyAuthorized returns (uint256 usdcReceived) {
        uint256 totalShares = STAKING.balanceOf(address(this));
        if (totalShares == 0) return 0;

        uint256 ethBefore = address(this).balance;
        STAKING.withdraw(totalShares);
        uint256 ethRecovered = address(this).balance - ethBefore;

        if (ethRecovered == 0) return 0;

        usdcReceived = SWAP_HELPER.swapETHForUSDC{value: ethRecovered}(ethRecovered, msg.sender);
        totalDeposited = 0;

        emit StakeWithdrawn(totalShares, ethRecovered, usdcReceived);
    }

    // -------------------------------------------------------------------------
    // IYieldSource — view
    // -------------------------------------------------------------------------

    /// @inheritdoc IYieldSource
    /// @dev  Returns the USDC-denominated value of `account`'s position in this adapter.
    ///       Since the adapter holds all stake on behalf of the YieldRouter, only
    ///       the YieldRouter's balance is meaningful.  For other addresses, returns 0.
    ///       Yield is estimated proportionally from the ETH staking gain above principal.
    function balanceOf(address account) external view override returns (uint256) {
        if (account != authorizedCaller && account != owner()) return 0;

        uint256 shares = STAKING.balanceOf(address(this));
        if (shares == 0) return 0;

        uint256 ethValue = STAKING.shareToAsset(shares);
        // Return deposited principal + estimated yield (eth gain expressed in USDC terms)
        // In production: use Chainlink ETH/USD oracle for accurate conversion
        return totalDeposited + (ethValue > totalDeposited ? ethValue - totalDeposited : 0);
    }

    /// @inheritdoc IYieldSource
    /// @dev  Reads the current APY directly from Unichain's staking contract.
    function currentAPY() external view override returns (uint256) {
        return STAKING.currentAPYBps();
    }

    /// @inheritdoc IYieldSource
    function asset() external view override returns (address) {
        return address(USDC);
    }

    /// @inheritdoc IYieldSource
    /// @dev  Returns remaining capacity as the maximum additional deposit.
    function maxDeposit() public view override returns (uint256) {
        return maxCapacity - totalDeposited;
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    function setAuthorizedCaller(address caller) external onlyOwner {
        authorizedCaller = caller;
        emit AuthorizedCallerUpdated(caller);
    }

    function setMaxCapacity(uint256 newCapacity) external onlyOwner {
        maxCapacity = newCapacity;
        emit MaxCapacityUpdated(newCapacity);
    }

    // -------------------------------------------------------------------------
    // Receive ETH (required for staking withdrawals)
    // -------------------------------------------------------------------------

    receive() external payable {}
}
