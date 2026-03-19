// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title APYVerifier
/// @notice TWAP-based APY anomaly detector for yield source validation.
///
/// @dev    Prevents routing capital to a compromised adapter that is suddenly
///         reporting an inflated APY (e.g. a price manipulation or oracle hack).
///
///         Algorithm:
///           1.  Maintain a circular buffer of the last N_SAMPLES APY readings.
///           2.  Compute a simple time-weighted average (TWAP) from the buffer.
///           3.  Reject any new reading that deviates from the TWAP by more than
///               MAX_DEVIATION_BPS basis points.
///           4.  If fewer than 2 samples have been collected, accept any reading
///               (no prior history to compare against).
///
///         The TWAP does NOT weight samples by time elapsed; all samples are
///         treated equally.  For longer-term accuracy, callers should call
///         APYVerifier.update() on every routeToBestSource invocation.
///
/// @custom:security  Storage library — callers must pass `storage` references.
library APYVerifier {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Maximum allowable absolute deviation from the TWAP expressed in bps.
    ///         200 bps = 2.00% absolute.  E.g. TWAP of 500 bps allows readings
    ///         in [300, 700] bps before the anomaly check triggers.
    uint256 internal constant MAX_DEVIATION_BPS = 200;

    /// @notice Number of samples kept in the circular buffer.
    uint8 internal constant N_SAMPLES = 8;

    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    /// @notice Circular buffer of APY readings for one yield source.
    /// @dev    Packs tightly: 8×uint256 = 256 bytes + 2 bytes overhead.
    ///         All fields are updated only through `update()`.
    struct APYSnapshot {
        uint256[8] samples; // circular buffer of raw APY readings (in bps)
        uint8 head;         // next write index (0..7)
        uint8 count;        // number of valid samples collected so far (max 8)
    }

    // -------------------------------------------------------------------------
    // Write
    // -------------------------------------------------------------------------

    /// @notice Record a new APY reading into the snapshot's circular buffer.
    ///         Overwrites the oldest sample once the buffer is full.
    ///
    /// @param snap    Storage reference to the source's APYSnapshot
    /// @param newAPY  Latest APY reading in basis points (100 = 1.00%)
    function update(APYSnapshot storage snap, uint256 newAPY) internal {
        snap.samples[snap.head] = newAPY;
        snap.head = (snap.head + 1) % N_SAMPLES;
        if (snap.count < N_SAMPLES) snap.count++;
    }

    // -------------------------------------------------------------------------
    // Read
    // -------------------------------------------------------------------------

    /// @notice Compute the simple moving average of all buffered APY readings.
    ///         Returns 0 if the buffer is empty.
    ///
    /// @param snap  Storage reference to the source's APYSnapshot
    /// @return avg  Average APY in basis points
    function twap(APYSnapshot storage snap) internal view returns (uint256 avg) {
        uint8 n = snap.count;
        if (n == 0) return 0;
        uint256 sum;
        for (uint256 i; i < n; ) {
            sum += snap.samples[i];
            unchecked { ++i; }
        }
        avg = sum / n;
    }

    /// @notice Returns true if `newAPY` is within MAX_DEVIATION_BPS of the TWAP.
    ///
    ///         Edge cases:
    ///           - Fewer than 2 samples → always returns true (no history yet).
    ///           - TWAP of 0            → always returns true (avoid division by zero).
    ///           - newAPY exactly equals TWAP → returns true.
    ///
    /// @param snap    Storage reference to the source's APYSnapshot
    /// @param newAPY  Candidate APY reading in basis points
    /// @return        True if newAPY passes the TWAP deviation check
    function isWithinBounds(APYSnapshot storage snap, uint256 newAPY)
        internal
        view
        returns (bool)
    {
        // Not enough history — accept anything
        if (snap.count < 2) return true;

        uint256 avg = twap(snap);
        // TWAP is zero — accept anything (prevent division by zero)
        if (avg == 0) return true;

        uint256 deviation = newAPY > avg ? newAPY - avg : avg - newAPY;
        // deviation as a fraction of TWAP, expressed in bps
        return (deviation * 10_000) / avg <= MAX_DEVIATION_BPS;
    }
}
