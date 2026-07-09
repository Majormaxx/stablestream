// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";

/// @title IIdleCapitalYieldModule
/// @notice Public interface that hook developers and RSC deployers code against.
///         Any contract implementing this interface can be monitored by RangeMonitorRSC.
///
/// @dev    An RSC deployer on Reactive Network instantiates RangeMonitorRSC pointed
///         at any hook that implements these events and functions. The event signatures
///         are the contract — the RSC watches them and dispatches callbacks.
interface IIdleCapitalYieldModule {
    // -------------------------------------------------------------------------
    // Events monitored by RangeMonitorRSC
    // -------------------------------------------------------------------------

    /// @notice Emitted when afterSwap detects a position exited its active range.
    ///         The RSC watches this to trigger routeToYield().
    event PositionLeftRange(bytes32 indexed positionId, int24 newTick);

    /// @notice Emitted when beforeSwap detects a swap will re-enter a position's range.
    ///         The RSC watches this to trigger recallFromYield() JIT.
    event PositionEnteredRange(bytes32 indexed positionId, int24 currentTick);

    /// @notice Emitted after capital is successfully routed to a yield source
    event CapitalRouted(
        bytes32 indexed positionId,
        address indexed yieldSource,
        uint256 amount
    );

    /// @notice Emitted after capital is recalled from a yield source and re-added as liquidity
    event CapitalRecalled(
        bytes32 indexed positionId,
        address indexed yieldSource,
        uint256 received,
        uint128 newLiquidity
    );

    // -------------------------------------------------------------------------
    // External functions callable by RangeMonitorRSC
    // -------------------------------------------------------------------------

    /// @notice Removes idle out-of-range liquidity and deposits it to a yield source
    function routeToYield(bytes32 positionId) external;

    /// @notice Recalls capital from a yield source and re-adds it as liquidity (JIT)
    function recallFromYield(bytes32 positionId) external;

    /// @notice Sets the RSC address authorised to trigger routing callbacks
    function setReactiveContract(address rsc) external;

    // -------------------------------------------------------------------------
    // View functions
    // -------------------------------------------------------------------------

    /// @notice Returns the full on-chain state of a position
    function getPosition(bytes32 positionId) external view returns (bytes memory);

    /// @notice Computes the deterministic position ID for owner + pool + range
    function computePositionId(
        address owner_,
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper
    ) external pure returns (bytes32);
}
