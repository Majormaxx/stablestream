// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title DynamicFeeModule
/// @notice Computes swap fees that scale with the fraction of pool capital
///         currently deployed to external yield sources.
///
/// @dev    Fee schedule:
///           yieldRatio = yieldCapital / totalPoolCapital  (1e18 fixed-point)
///           fee = BASE_FEE + (yieldRatio × MAX_YIELD_PREMIUM / 1e18)
///
///           yieldRatio = 0%   →  BASE_FEE            = 3000 bps (0.30%)
///           yieldRatio = 50%  →  BASE_FEE + 1250 bps = 4250 bps (0.425%)
///           yieldRatio = 100% →  BASE_FEE + 2500 bps = 5500 bps (0.55%)
///
///         Rationale: when the pool has less active liquidity (because capital is in
///         yield), every swap has higher price impact.  A higher fee compensates LPs
///         for that risk and disincentivises MEV around the recall window.
///
///         All constants expressed in Uniswap v4 fee units (hundredths of a bip).
///         1 bip = 0.01%, so 3000 = 0.30%.
///
/// @custom:security  This is a pure library — no storage, no reentrancy risk.
library DynamicFeeModule {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Base fee applied when no capital is in yield (pool fully liquid).
    uint24 public constant BASE_FEE = 3000; // 0.30%

    /// @notice Maximum additional fee when 100% of pool capital is in yield.
    uint24 public constant MAX_YIELD_PREMIUM = 2500; // +0.25%

    /// @notice Absolute hard cap on the computed fee regardless of yield ratio.
    uint24 public constant MAX_FEE = 10000; // 1.00%

    // -------------------------------------------------------------------------
    // Core function
    // -------------------------------------------------------------------------

    /// @notice Compute the dynamic LP fee for the current pool state.
    ///
    /// @param totalCapital   Total USDC principal tracked by this pool
    ///                       (in-pool + in-yield, in token's native decimals).
    /// @param yieldCapital   USDC currently routed to external yield sources.
    ///                       Must be ≤ totalCapital; silently capped to totalCapital
    ///                       if not (defensive).
    ///
    /// @return fee           Fee in Uniswap v4 units (hundredths of a bip).
    ///                       Always within [BASE_FEE, MAX_FEE].
    function computeFee(uint256 totalCapital, uint256 yieldCapital)
        internal
        pure
        returns (uint24 fee)
    {
        // No capital tracked or nothing in yield → base fee
        if (totalCapital == 0 || yieldCapital == 0) return BASE_FEE;

        // Cap yieldCapital defensively to prevent overflow in edge cases
        if (yieldCapital > totalCapital) yieldCapital = totalCapital;

        // yieldRatio in 1e18 fixed-point (range: 0..1e18)
        uint256 yieldRatio = (yieldCapital * 1e18) / totalCapital;

        // Linear interpolation between BASE_FEE and BASE_FEE + MAX_YIELD_PREMIUM
        uint256 premium = (yieldRatio * uint256(MAX_YIELD_PREMIUM)) / 1e18;
        uint256 computed = uint256(BASE_FEE) + premium;

        // Apply hard cap
        fee = computed > uint256(MAX_FEE) ? MAX_FEE : uint24(computed);
    }
}
