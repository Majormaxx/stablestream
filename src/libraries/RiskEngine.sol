// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title RiskEngine
/// @notice Risk-weighted yield source scoring for institutional-grade capital allocation.
///
/// @dev    Risk framework:
///           Each registered yield source carries a RiskProfile set by the owner.
///           When an LP deposits, they specify their risk tolerance (0–5 scale).
///           The router filters out sources whose riskScore exceeds the LP's
///           maximum tolerated risk level, then ranks remaining sources by their
///           risk-adjusted APY rather than raw APY.
///
///         Risk-adjusted APY formula:
///           adjustedAPY = rawAPY × (100 - riskScore) / 100
///
///         Example:
///           Source A: rawAPY = 800 bps, riskScore = 60  → adjusted = 320 bps
///           Source B: rawAPY = 500 bps, riskScore = 10  → adjusted = 450 bps
///           → Router prefers Source B despite lower raw APY.
///
///         Tolerance-to-max-risk mapping (lpTolerance × 20):
///           0 → maxRisk =   0 (only riskScore 0 sources)
///           1 → maxRisk =  20 (low risk only)
///           2 → maxRisk =  40 (moderate risk)
///           3 → maxRisk =  60 (medium-high risk)
///           4 → maxRisk =  80 (high risk)
///           5 → maxRisk = 100 (any source — default for automated routing)
///
/// @custom:security  Pure library — no storage, no reentrancy risk.
library RiskEngine {
    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    /// @notice On-chain risk metadata for a single yield source.
    /// @dev    Packed into ≤ 32 bytes: uint16 + uint8 + bool + bool + uint64 = 12 bytes.
    struct RiskProfile {
        /// @dev Composite risk score 0 (safest) to 100 (riskiest).
        ///      Factors in smart contract risk, oracle dependency, and liquidity risk.
        uint16 riskScore;
        /// @dev TVL tier: 1 = >$1B, 2 = >$100M, 3 = >$10M, 4 = <$10M.
        ///      Higher TVL → lower risk → lower riskScore contribution.
        uint8 tvlTier;
        /// @dev True when the protocol has undergone at least one public audit.
        bool isAudited;
        /// @dev True when the protocol has active on-chain insurance (e.g. Nexus Mutual).
        bool hasInsurance;
        /// @dev Seconds since the protocol's first production deployment.
        ///      Older protocols are considered more battle-tested.
        uint64 deploymentAge;
    }

    // -------------------------------------------------------------------------
    // Core functions
    // -------------------------------------------------------------------------

    /// @notice Compute the risk-adjusted APY for a source.
    ///         Penalises high-risk sources by scaling down their raw APY.
    ///
    /// @param rawAPY   Reported APY in basis points (e.g. 500 = 5.00%)
    /// @param profile  Risk metadata for the source
    /// @return         Adjusted APY in basis points (always ≤ rawAPY)
    function riskAdjustedAPY(uint256 rawAPY, RiskProfile memory profile)
        internal
        pure
        returns (uint256)
    {
        // Clamp riskScore to 100 so an out-of-range value never causes an underflow
        // revert. A clamped score of 100 yields safetyMultiplier=0 (adjustedAPY=0),
        // causing the router to skip the misconfigured source instead of reverting.
        uint256 score = profile.riskScore > 100 ? 100 : uint256(profile.riskScore);
        uint256 safetyMultiplier = 100 - score;
        return (rawAPY * safetyMultiplier) / 100;
    }

    /// @notice Returns true when a source's risk profile is within an LP's tolerance.
    ///
    /// @param profile      Risk metadata for the source
    /// @param lpTolerance  LP's risk tolerance on a 0–5 scale (5 = most tolerant)
    /// @return             True if the source's riskScore ≤ lpTolerance × 20
    function meetsThreshold(RiskProfile memory profile, uint8 lpTolerance)
        internal
        pure
        returns (bool)
    {
        // Clamp lpTolerance to its documented 0–5 range (Finding d24db16a).
        // Values > 5 would produce maxRisk > 100, silently disabling the filter.
        uint8 tolerance = lpTolerance > 5 ? 5 : lpTolerance;
        // tolerance 5 → maxRisk 100, which accepts every valid riskScore (0..100)
        uint16 maxRisk = uint16(tolerance) * 20;
        return profile.riskScore <= maxRisk;
    }

    /// @notice Convenience: returns both adjusted APY and threshold check in one call.
    ///
    /// @param rawAPY       Reported APY in basis points
    /// @param profile      Risk metadata for the source
    /// @param lpTolerance  LP's risk tolerance (0–5)
    /// @return adjusted    Risk-adjusted APY (0 if source fails threshold)
    /// @return passes      True if source meets the LP's risk tolerance
    function evaluate(uint256 rawAPY, RiskProfile memory profile, uint8 lpTolerance)
        internal
        pure
        returns (uint256 adjusted, bool passes)
    {
        passes = meetsThreshold(profile, lpTolerance);
        adjusted = passes ? riskAdjustedAPY(rawAPY, profile) : 0;
    }
}
