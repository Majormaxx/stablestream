// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DynamicFeeModule} from "../src/DynamicFeeModule.sol";

/// @title DynamicFeeTest
/// @notice Unit tests for DynamicFeeModule.
///         Verifies fee computation at boundary conditions and linear interpolation.
contract DynamicFeeTest is Test {
    // -------------------------------------------------------------------------
    // Boundary conditions
    // -------------------------------------------------------------------------

    /// @notice When no capital is tracked (totalCapital == 0), returns BASE_FEE.
    function test_computeFee_returnsBaseFeeWhenZeroTotal() public pure {
        uint24 fee = DynamicFeeModule.computeFee(0, 0);
        assertEq(fee, DynamicFeeModule.BASE_FEE, "zero total capital must return BASE_FEE");
    }

    /// @notice When no capital is in yield (yieldCapital == 0), returns BASE_FEE.
    function test_computeFee_returnsBaseFeeWhenNoYield() public pure {
        uint24 fee = DynamicFeeModule.computeFee(100_000e6, 0);
        assertEq(fee, DynamicFeeModule.BASE_FEE, "zero yield capital must return BASE_FEE");
    }

    /// @notice When 100% of capital is in yield, returns BASE_FEE + MAX_YIELD_PREMIUM.
    function test_computeFee_returnsMaxPremiumWhenFullyDeployed() public pure {
        uint24 expected = DynamicFeeModule.BASE_FEE + DynamicFeeModule.MAX_YIELD_PREMIUM;
        uint24 fee = DynamicFeeModule.computeFee(100_000e6, 100_000e6);
        assertEq(fee, expected, "100% yield utilisation must return BASE_FEE + MAX_YIELD_PREMIUM");
    }

    /// @notice Fee must never exceed MAX_FEE even with extreme inputs.
    function test_computeFee_neverExceedsMaxFee() public pure {
        // Force a very high premium by setting yieldCapital > totalCapital
        // The function caps yieldCapital defensively.
        uint24 fee = DynamicFeeModule.computeFee(1, type(uint256).max);
        assertLe(fee, DynamicFeeModule.MAX_FEE, "fee must never exceed MAX_FEE");
    }

    // -------------------------------------------------------------------------
    // Linear interpolation
    // -------------------------------------------------------------------------

    /// @notice At 50% yield utilisation the fee is exactly halfway between
    ///         BASE_FEE and BASE_FEE + MAX_YIELD_PREMIUM.
    function test_computeFee_scalesLinearlyAtFiftyPercent() public pure {
        uint256 total = 200_000e6;
        uint256 inYield = 100_000e6; // 50%

        uint24 fee = DynamicFeeModule.computeFee(total, inYield);
        uint24 expected = DynamicFeeModule.BASE_FEE + DynamicFeeModule.MAX_YIELD_PREMIUM / 2;

        // Allow ±1 bps rounding from integer division
        assertApproxEqAbs(uint256(fee), uint256(expected), 1, "50% yield must yield ~midpoint fee");
    }

    /// @notice At 25% yield utilisation the fee is BASE_FEE + 25% of MAX_YIELD_PREMIUM.
    function test_computeFee_scalesLinearlyAtTwentyFivePercent() public pure {
        uint256 total = 100_000e6;
        uint256 inYield = 25_000e6; // 25%

        uint24 fee = DynamicFeeModule.computeFee(total, inYield);
        uint24 expected = DynamicFeeModule.BASE_FEE + DynamicFeeModule.MAX_YIELD_PREMIUM / 4;

        assertApproxEqAbs(uint256(fee), uint256(expected), 1, "25% yield must yield ~quarter-point fee");
    }

    // -------------------------------------------------------------------------
    // Constants sanity
    // -------------------------------------------------------------------------

    /// @notice BASE_FEE < BASE_FEE + MAX_YIELD_PREMIUM < MAX_FEE.
    function test_constants_areWellOrdered() public pure {
        assertGt(
            uint256(DynamicFeeModule.BASE_FEE + DynamicFeeModule.MAX_YIELD_PREMIUM),
            uint256(DynamicFeeModule.BASE_FEE),
            "premium must be positive"
        );
        assertLt(
            uint256(DynamicFeeModule.BASE_FEE + DynamicFeeModule.MAX_YIELD_PREMIUM),
            uint256(DynamicFeeModule.MAX_FEE),
            "max premium must be below MAX_FEE"
        );
    }

    /// @notice yieldCapital > totalCapital is silently capped (defensive).
    function test_computeFee_handlesYieldExceedingTotal() public pure {
        uint24 fee = DynamicFeeModule.computeFee(50_000e6, 100_000e6);
        // Should treat it as 100% utilisation
        uint24 expected = DynamicFeeModule.BASE_FEE + DynamicFeeModule.MAX_YIELD_PREMIUM;
        assertEq(fee, expected, "yield > total should be treated as 100% utilisation");
    }
}
