// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {APYVerifier} from "../src/libraries/APYVerifier.sol";

/// @title APYVerifierTest
/// @notice Unit tests for the APYVerifier TWAP anomaly-detection library.
///         Exercises the circular buffer, TWAP calculation, and bounds checking.
contract APYVerifierTest is Test {
    using APYVerifier for APYVerifier.APYSnapshot;

    // -------------------------------------------------------------------------
    // Storage helper — APYSnapshot must live in storage for library functions
    // -------------------------------------------------------------------------

    mapping(bytes32 => APYVerifier.APYSnapshot) private _snaps;

    function _snap(bytes32 key) internal returns (APYVerifier.APYSnapshot storage) {
        return _snaps[key];
    }

    // -------------------------------------------------------------------------
    // update() — circular buffer
    // -------------------------------------------------------------------------

    /// @notice update() stores readings and increments count up to N_SAMPLES.
    function test_update_storesReadingsAndIncrementsCount() public {
        APYVerifier.APYSnapshot storage snap = _snap("s1");

        snap.update(300);
        assertEq(snap.count, 1, "count should be 1 after first update");
        assertEq(snap.samples[0], 300, "first sample should be 300");

        snap.update(320);
        assertEq(snap.count, 2, "count should be 2 after second update");
        assertEq(snap.samples[1], 320, "second sample should be 320");
    }

    /// @notice count is capped at N_SAMPLES (8); buffer wraps around.
    function test_update_capsCountAtNSamples() public {
        APYVerifier.APYSnapshot storage snap = _snap("s2");

        for (uint256 i = 0; i < 10; i++) {
            snap.update(uint256(300 + i));
        }
        assertEq(snap.count, 8, "count must not exceed N_SAMPLES");
    }

    // -------------------------------------------------------------------------
    // twap() — moving average
    // -------------------------------------------------------------------------

    /// @notice twap() returns 0 on an empty snapshot.
    function test_twap_returnsZeroForEmptySnapshot() public {
        APYVerifier.APYSnapshot storage snap = _snap("s3");
        assertEq(APYVerifier.twap(snap), 0, "empty snapshot TWAP must be 0");
    }

    /// @notice twap() computes the correct average of all samples.
    function test_twap_returnsCorrectAverage() public {
        APYVerifier.APYSnapshot storage snap = _snap("s4");

        // Insert 4 known values: 200, 300, 400, 500 → avg = 350
        snap.update(200);
        snap.update(300);
        snap.update(400);
        snap.update(500);

        assertEq(APYVerifier.twap(snap), 350, "TWAP should be average of all samples");
    }

    /// @notice twap() of a single sample equals that sample.
    function test_twap_singleSampleEqualsSelf() public {
        APYVerifier.APYSnapshot storage snap = _snap("s5");
        snap.update(420);
        assertEq(APYVerifier.twap(snap), 420, "single-sample TWAP must equal the sample");
    }

    // -------------------------------------------------------------------------
    // isWithinBounds() — anomaly detection
    // -------------------------------------------------------------------------

    /// @notice Fresh snapshot (count < 2) always accepts any reading.
    function test_isWithinBounds_returnsTrueForFreshSnapshot() public {
        APYVerifier.APYSnapshot storage snap = _snap("s6");

        // Zero samples
        assertTrue(APYVerifier.isWithinBounds(snap, 9999), "0 samples: any value accepted");

        // One sample
        snap.update(300);
        assertTrue(APYVerifier.isWithinBounds(snap, 9999), "1 sample: any value accepted");
    }

    /// @notice A reading 3× the TWAP is rejected as anomalous.
    function test_isWithinBounds_rejectsAnomalousSpike() public {
        APYVerifier.APYSnapshot storage snap = _snap("s7");

        // Seed: TWAP ≈ 300 bps
        snap.update(300);
        snap.update(300);

        // 900 bps is 3× the TWAP — a 200% deviation, far above MAX_DEVIATION_BPS (2%)
        assertFalse(APYVerifier.isWithinBounds(snap, 900), "3x spike must be rejected");
    }

    /// @notice A reading within ±1% of TWAP is accepted as normal variation.
    function test_isWithinBounds_acceptsNormalVariation() public {
        APYVerifier.APYSnapshot storage snap = _snap("s8");

        // Seed: TWAP = 400 bps
        snap.update(400);
        snap.update(400);

        // ±4 bps on a 400 bps TWAP = 1% deviation, within MAX_DEVIATION_BPS (2%)
        assertTrue(APYVerifier.isWithinBounds(snap, 404), "1% above TWAP must be accepted");
        assertTrue(APYVerifier.isWithinBounds(snap, 396), "1% below TWAP must be accepted");
    }

    /// @notice A reading exactly at MAX_DEVIATION_BPS boundary is accepted.
    function test_isWithinBounds_acceptsExactBoundary() public {
        APYVerifier.APYSnapshot storage snap = _snap("s9");

        // TWAP = 1000 bps; MAX_DEVIATION_BPS = 200 → max deviation = 20 bps
        snap.update(1000);
        snap.update(1000);

        assertTrue(APYVerifier.isWithinBounds(snap, 1020), "exact boundary must be accepted");
        assertTrue(APYVerifier.isWithinBounds(snap, 980),  "exact lower boundary must be accepted");
    }

    /// @notice A TWAP of 0 (all samples are 0) accepts any reading.
    function test_isWithinBounds_returnsTrueWhenTwapIsZero() public {
        APYVerifier.APYSnapshot storage snap = _snap("s10");

        snap.update(0);
        snap.update(0);

        // TWAP = 0 → avoid division by zero, accept all
        assertTrue(APYVerifier.isWithinBounds(snap, 9999), "zero TWAP must accept any reading");
    }
}
