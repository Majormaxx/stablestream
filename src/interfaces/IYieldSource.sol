// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IYieldSource
/// @notice Interface that every yield adapter must implement so YieldRouter can
///         treat Aave, Compound, and future sources identically.
/// @dev    All amounts are expressed in the underlying asset (e.g., USDC with 6 decimals).
///         APY is expressed in basis points (10_000 = 100%).
interface IYieldSource {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when a deposit or withdrawal exceeds the adapter's capacity
    error ExceedsCapacity(uint256 requested, uint256 available);

    /// @notice Thrown when a zero-amount operation is attempted
    error ZeroAmount();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted on every successful deposit
    event Deposited(address indexed caller, uint256 amount, uint256 shares);

    /// @notice Emitted on every successful withdrawal
    event Withdrawn(address indexed caller, uint256 amount, uint256 received);

    // -------------------------------------------------------------------------
    // Mutative
    // -------------------------------------------------------------------------

    /// @notice Deposits `amount` of the underlying asset into the yield source.
    ///         The caller must have approved this adapter to spend `amount` tokens
    ///         before calling.
    /// @param  amount  Quantity of underlying tokens to deposit
    /// @return shares  Yield-bearing shares (or receipt tokens) credited to caller
    function deposit(uint256 amount) external returns (uint256 shares);

    /// @notice Withdraws exactly `amount` of the underlying asset.
    ///         May receive slightly less if the protocol charges withdrawal fees.
    /// @param  amount    Underlying tokens to redeem
    /// @return received  Actual underlying tokens received by the caller
    function withdraw(uint256 amount) external returns (uint256 received);

    /// @notice Withdraws the entire balance belonging to the caller.
    ///         Useful for emergency recalls or full position exits.
    /// @return received  Total underlying tokens returned to the caller
    function withdrawAll() external returns (uint256 received);

    // -------------------------------------------------------------------------
    // View
    // -------------------------------------------------------------------------

    /// @notice Returns the current value (principal + accrued yield) held by `account`
    /// @param  account  Address to query
    /// @return          Balance in underlying token units
    function balanceOf(address account) external view returns (uint256);

    /// @notice Returns the current supply APY in basis points (1% = 100 bps)
    /// @dev    Implementations should return 0 when the rate cannot be fetched rather
    ///         than reverting, so YieldRouter can always compare sources safely.
    /// @return APY in basis points
    function currentAPY() external view returns (uint256);

    /// @notice Returns the ERC-20 address of the underlying asset
    function asset() external view returns (address);

    /// @notice Returns the maximum additional deposit the adapter will accept.
    ///         Returns type(uint256).max when there is no cap.
    function maxDeposit() external view returns (uint256);
}
