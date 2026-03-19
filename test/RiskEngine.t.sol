// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {RiskEngine} from "../src/libraries/RiskEngine.sol";

/// @title RiskEngineTest
/// @notice Unit tests for the RiskEngine risk-scoring library.
///         Verifies riskAdjustedAPY, meetsThreshold, and the evaluate convenience
///         function across a range of risk profiles and tolerance levels.
contract RiskEngineTest is Test {
    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _profile(uint16 score) internal pure returns (RiskEngine.RiskProfile memory) {
        return RiskEngine.RiskProfile({
            riskScore: score,
            tvlTier: 1,
            isAudited: true,
            hasInsurance: false,
            deploymentAge: 365 days
        });
    }

    // -------------------------------------------------------------------------
    // riskAdjustedAPY()
    // -------------------------------------------------------------------------

    /// @notice riskScore = 0 (safest) → full APY returned unchanged.
    function test_riskAdjustedAPY_zeroRiskReturnsFullAPY() public pure {
        uint256 rawAPY = 500; // 5.00%
        uint256 adj = RiskEngine.riskAdjustedAPY(rawAPY, _profile(0));
        assertEq(adj, rawAPY, "riskScore 0 must return full APY");
    }

    /// @notice riskScore = 100 (riskiest) → adjusted APY is 0.
    function test_riskAdjustedAPY_maxRiskReturnsZero() public pure {
        uint256 rawAPY = 800; // 8.00%
        uint256 adj = RiskEngine.riskAdjustedAPY(rawAPY, _profile(100));
        assertEq(adj, 0, "riskScore 100 must return 0 adjusted APY");
    }

    /// @notice riskScore = 50 → exactly half of raw APY.
    function test_riskAdjustedAPY_halfRiskHalvesAPY() public pure {
        uint256 rawAPY = 600; // 6.00%
        uint256 adj = RiskEngine.riskAdjustedAPY(rawAPY, _profile(50));
        assertEq(adj, 300, "riskScore 50 must return 50% of raw APY");
    }

    /// @notice riskScore = 20 → 80% of raw APY.
    function test_riskAdjustedAPY_twentyRiskReturnsEightyPercent() public pure {
        uint256 rawAPY = 500;
        uint256 adj = RiskEngine.riskAdjustedAPY(rawAPY, _profile(20));
        assertEq(adj, 400, "riskScore 20 must return 80% of raw APY");
    }

    /// @notice riskAdjustedAPY is always ≤ rawAPY.
    function test_riskAdjustedAPY_neverExceedsRaw(uint16 score, uint256 rawAPY) public pure {
        vm.assume(score <= 100);
        vm.assume(rawAPY <= 100_000);
        uint256 adj = RiskEngine.riskAdjustedAPY(rawAPY, _profile(score));
        assertLe(adj, rawAPY, "adjusted APY must never exceed raw APY");
    }

    // -------------------------------------------------------------------------
    // meetsThreshold()
    // -------------------------------------------------------------------------

    /// @notice Tolerance 0 → only riskScore 0 passes.
    function test_meetsThreshold_zeroToleranceOnlyAcceptsZeroRisk() public pure {
        assertTrue(RiskEngine.meetsThreshold(_profile(0), 0),  "riskScore 0, tolerance 0: pass");
        assertFalse(RiskEngine.meetsThreshold(_profile(1), 0), "riskScore 1, tolerance 0: fail");
    }

    /// @notice Tolerance 5 → any riskScore 0..100 passes.
    function test_meetsThreshold_maxToleranceAcceptsAll() public pure {
        assertTrue(RiskEngine.meetsThreshold(_profile(0),   5), "riskScore   0, tolerance 5: pass");
        assertTrue(RiskEngine.meetsThreshold(_profile(50),  5), "riskScore  50, tolerance 5: pass");
        assertTrue(RiskEngine.meetsThreshold(_profile(100), 5), "riskScore 100, tolerance 5: pass");
    }

    /// @notice Tolerance 3 → maxRisk = 60; riskScore 60 passes, 61 fails.
    function test_meetsThreshold_borderlineCase() public pure {
        assertTrue(RiskEngine.meetsThreshold(_profile(60), 3), "riskScore 60 <= 60: pass");
        assertFalse(RiskEngine.meetsThreshold(_profile(61), 3), "riskScore 61 > 60: fail");
    }

    // -------------------------------------------------------------------------
    // evaluate() — combined helper
    // -------------------------------------------------------------------------

    /// @notice When source fails threshold, evaluate returns (0, false).
    function test_evaluate_returnsFalseAndZeroWhenThresholdFails() public pure {
        (uint256 adj, bool passes) = RiskEngine.evaluate(500, _profile(80), 2);
        // tolerance 2 → maxRisk 40; riskScore 80 > 40 → fail
        assertFalse(passes, "should fail threshold");
        assertEq(adj, 0, "adjusted APY should be 0 when threshold fails");
    }

    /// @notice When source passes threshold, evaluate returns (adjustedAPY, true).
    function test_evaluate_returnsTrueAndAdjustedAPYWhenPasses() public pure {
        // tolerance 5 → all pass; riskScore 50 → 50% adjustment
        (uint256 adj, bool passes) = RiskEngine.evaluate(400, _profile(50), 5);
        assertTrue(passes, "should pass threshold at tolerance 5");
        assertEq(adj, 200, "adjusted APY should be 50% of 400 bps");
    }
}
