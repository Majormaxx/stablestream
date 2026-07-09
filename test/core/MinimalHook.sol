// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {IdleCapitalYieldModule} from "../../src/core/IdleCapitalYieldModule.sol";
import {YieldRouter} from "../../src/core/YieldRouter.sol";

/// @title MinimalHook
/// @notice Minimal example of a custom hook built on IdleCapitalYieldModule.
///         No NFT, no multi-token, no frontend — just the yield routing primitive.
///
/// @dev    A hook developer would write exactly this contract to get automatic
///         idle-capital yield routing. Deploy a YieldRouter with adapters, point
///         RangeMonitorRSC at the hook address, and call setReactiveContract().
///
///         This file serves as:
///           1. Proof that IdleCapitalYieldModule is a standalone reusable module
///           2. The worked example for docs/INTEGRATION_GUIDE.md
///
/// @custom:example
///   RangeMonitorRSC rsc = new RangeMonitorRSC{value: 0.3 ether}(
///     address(minimalHook), ORIGIN_CHAIN_ID, DEST_CHAIN_ID
///   );
///   minimalHook.setReactiveContract(address(rsc));
contract MinimalHook is IdleCapitalYieldModule {
    constructor(
        IPoolManager _poolManager,
        YieldRouter _yieldRouter,
        address _usdc,
        address _owner
    ) IdleCapitalYieldModule(_poolManager, _yieldRouter, _usdc, _owner) {}
}
