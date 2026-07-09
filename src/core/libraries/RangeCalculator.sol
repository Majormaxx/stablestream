// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/// @title RangeCalculator
/// @notice Pure utility functions for tick-range status checks used by StableStreamHook.
/// @dev    All functions are pure so they can be called without storage access costs.
library RangeCalculator {
    // -------------------------------------------------------------------------
    // Core checks
    // -------------------------------------------------------------------------

    /// @notice Returns true when `currentTick` falls within the closed interval
    ///         [tickLower, tickUpper).  Follows Uniswap v4 convention: a position
    ///         earns fees when tickLower <= currentTick < tickUpper.
    /// @param currentTick  Live tick read from PoolManager slot0
    /// @param tickLower    Lower bound of the LP position
    /// @param tickUpper    Upper bound of the LP position
    function isInRange(int24 currentTick, int24 tickLower, int24 tickUpper)
        internal
        pure
        returns (bool)
    {
        return currentTick >= tickLower && currentTick < tickUpper;
    }

    /// @notice Returns true when the position just left its active range.
    ///         Useful in afterSwap to detect the exact transition from earning
    ///         fees to idle.
    /// @param prevTick     Tick before the swap
    /// @param newTick      Tick after the swap
    /// @param tickLower    Lower bound of the LP position
    /// @param tickUpper    Upper bound of the LP position
    function crossedOutOfRange(
        int24 prevTick,
        int24 newTick,
        int24 tickLower,
        int24 tickUpper
    ) internal pure returns (bool) {
        bool wasin = isInRange(prevTick, tickLower, tickUpper);
        bool isNow = isInRange(newTick, tickLower, tickUpper);
        return wasin && !isNow;
    }

    /// @notice Returns true when the position just entered its active range.
    ///         Useful in beforeSwap to decide whether a JIT recall is needed.
    /// @param prevTick  Tick before the swap
    /// @param newTick   Tick after the swap
    /// @param tickLower Lower bound of the LP position
    /// @param tickUpper Upper bound of the LP position
    function crossedIntoRange(
        int24 prevTick,
        int24 newTick,
        int24 tickLower,
        int24 tickUpper
    ) internal pure returns (bool) {
        bool wasin = isInRange(prevTick, tickLower, tickUpper);
        bool isNow = isInRange(newTick, tickLower, tickUpper);
        return !wasin && isNow;
    }

    /// @notice Estimates the tick value after a swap by checking in which
    ///         direction the swap moves the price.
    ///         This is a lightweight heuristic — exact post-swap tick is unknown
    ///         inside beforeSwap — so we approximate based on zeroForOne direction
    ///         and the target sqrtPriceLimit supplied by the swapper.
    /// @param currentTick      Current pool tick
    /// @param zeroForOne       True when swapping token0 → token1 (price decreases)
    /// @param sqrtPriceLimitX96 The price limit the swapper set
    /// @return estimatedTick   Conservative estimate of the post-swap tick
    function estimatePostSwapTick(
        int24 currentTick,
        bool zeroForOne,
        uint160 sqrtPriceLimitX96
    ) internal pure returns (int24 estimatedTick) {
        // If the price limit is 0 (no limit set by the swapper), treat conservatively:
        // return the current tick so callers do NOT assume unlimited price movement.
        // Returning type(int24).min/max here caused false-positive recall triggers on
        // every unlimited swap (Finding 9830b75d); conservative treatment eliminates that.
        if (sqrtPriceLimitX96 == 0) {
            (zeroForOne); // silence unused-param warning
            return currentTick;
        }
        return TickMath.getTickAtSqrtPrice(sqrtPriceLimitX96);
    }

    /// @notice Returns true when a swap starting at `currentTick` with the
    ///         given direction could reach `tickLower..tickUpper`.
    ///         Used in beforeSwap for cheap JIT-recall eligibility check.
    /// @param currentTick        Current pool tick
    /// @param zeroForOne         Swap direction (true = price decreasing)
    /// @param sqrtPriceLimitX96  Swapper's price cap
    /// @param tickLower          Position's lower tick
    /// @param tickUpper          Position's upper tick
    function swapCouldEnterRange(
        int24 currentTick,
        bool zeroForOne,
        uint160 sqrtPriceLimitX96,
        int24 tickLower,
        int24 tickUpper
    ) internal pure returns (bool) {
        // Already in range — no recall needed (capital should already be in pool)
        if (isInRange(currentTick, tickLower, tickUpper)) return false;

        int24 est = estimatePostSwapTick(currentTick, zeroForOne, sqrtPriceLimitX96);

        if (zeroForOne) {
            // Price moving down: could enter range from above (currentTick > tickUpper)
            return currentTick >= tickUpper && est < tickUpper;
        } else {
            // Price moving up: could enter range from below (currentTick < tickLower)
            return currentTick < tickLower && est >= tickLower;
        }
    }
}
