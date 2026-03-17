// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title YieldAccounting
/// @notice Library for tracking per-position yield accrual inside StableStreamHook.
/// @dev    All arithmetic uses uint256 to avoid overflow; individual fields are
///         sized to pack efficiently into storage slots where possible.
library YieldAccounting {
    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    /// @notice Snapshot of a position's yield accounting state.
    ///         Stored inside StableStreamHook's mapping(bytes32 => TrackedPosition).
    struct YieldState {
        /// @dev  Principal deposited into the yield source (USDC units)
        uint128 depositedPrincipal;
        /// @dev  Cumulative yield harvested back to the user (USDC units)
        uint128 harvestedYield;
        /// @dev  Timestamp of the last yield-routing operation (for rate limiting)
        uint64 lastRouteTimestamp;
        /// @dev  Reserved for future use / struct packing
        uint64 _reserved;
    }

    // -------------------------------------------------------------------------
    // Pure helpers
    // -------------------------------------------------------------------------

    /// @notice Computes the gross yield earned on a position.
    ///         Gross yield = currentBalance - depositedPrincipal.
    ///         Returns 0 rather than reverting if currentBalance < depositedPrincipal
    ///         (can happen due to rounding in the underlying protocol).
    /// @param state          Current YieldState for the position
    /// @param currentBalance Current value reported by the yield adapter (principal + yield)
    /// @return yield         Gross yield earned, in underlying token units
    function grossYield(YieldState memory state, uint256 currentBalance)
        internal
        pure
        returns (uint256 yield)
    {
        uint256 principal = uint256(state.depositedPrincipal);
        if (currentBalance <= principal) return 0;
        unchecked {
            yield = currentBalance - principal;
        }
    }

    /// @notice Returns the net (unharvested) yield still sitting in the yield source.
    /// @param state          Current YieldState
    /// @param currentBalance Live balance from yield adapter
    /// @return               Net yield not yet returned to the user
    function pendingYield(YieldState memory state, uint256 currentBalance)
        internal
        pure
        returns (uint256)
    {
        uint256 gross = grossYield(state, currentBalance);
        uint256 harvested = uint256(state.harvestedYield);
        if (gross <= harvested) return 0;
        unchecked {
            return gross - harvested;
        }
    }

    /// @notice Records that `amount` of principal has been deposited to the yield source.
    ///         Safely casts to uint128; reverts on overflow (>3.4 × 10^20, safe for USDC).
    /// @param state   Storage pointer to the position's YieldState
    /// @param amount  Tokens deposited
    function recordDeposit(YieldState storage state, uint256 amount) internal {
        state.depositedPrincipal += uint128(amount);
        state.lastRouteTimestamp = uint64(block.timestamp);
    }

    /// @notice Records that `amount` of tokens (principal + yield) have been
    ///         recalled from the yield source.
    ///         Subtracts principal first; any surplus is counted as harvested yield.
    /// @param state   Storage pointer
    /// @param amount  Total tokens returned by the yield adapter
    function recordWithdrawal(YieldState storage state, uint256 amount) internal {
        uint256 principal = uint256(state.depositedPrincipal);

        if (amount >= principal) {
            // Full principal returned + some yield
            unchecked {
                uint256 yieldEarned = amount - principal;
                state.harvestedYield += uint128(yieldEarned);
            }
            state.depositedPrincipal = 0;
        } else {
            // Partial withdrawal (shouldn't happen in normal flow, but be safe)
            state.depositedPrincipal = uint128(principal - amount);
        }

        state.lastRouteTimestamp = uint64(block.timestamp);
    }

    /// @notice Returns true when enough time has passed since the last routing
    ///         action to justify another one.  Prevents excessive gas usage when
    ///         the pool is choppy and the tick crosses the range boundary rapidly.
    /// @param state      Current YieldState
    /// @param minDelay   Minimum seconds between routing actions (e.g., 60)
    function canRoute(YieldState memory state, uint256 minDelay)
        internal
        view
        returns (bool)
    {
        return block.timestamp >= uint256(state.lastRouteTimestamp) + minDelay;
    }
}
