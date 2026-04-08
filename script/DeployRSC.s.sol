// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {RangeMonitorRSC} from "../src/reactive/RangeMonitorRSC.sol";

/// @title DeployRSC
/// @notice Deploys RangeMonitorRSC on Reactive Network Lasna testnet (chain ID 5318007).
///
///         Run with:
///           forge script script/DeployRSC.s.sol:DeployRSC \
///             --rpc-url $REACTIVE_RPC \
///             --broadcast \
///             -vvvv
///
/// @custom:chain Reactive Network Lasna testnet — chain ID 5318007
contract DeployRSC is Script {

    // Origin = Unichain Sepolia (chain ID 1301)
    uint256 constant ORIGIN_CHAIN_ID = 1301;

    // Destination = Unichain Sepolia (callbacks go back to hook)
    uint256 constant DEST_CHAIN_ID = 1301;

    function run() external {
        // ── Chain-ID gate ─────────────────────────────────────────────────────
        require(block.chainid == 5318007, "DeployRSC: wrong chain - expected Reactive Network Lasna (5318007)");

        uint256 deployerKey = vm.envUint("REACTIVE_PRIVATE_KEY");
        address hookAddress  = vm.envAddress("STABLE_STREAM_HOOK_ADDRESS");

        // ── Validate hook address ─────────────────────────────────────────────
        require(hookAddress != address(0), "DeployRSC: STABLE_STREAM_HOOK_ADDRESS not set");

        address deployer = vm.addr(deployerKey);

        console2.log("=== RangeMonitorRSC Deployment ===");
        console2.log("Deployer:          ", deployer);
        console2.log("Chain ID:          ", block.chainid);
        console2.log("Origin chain:      ", ORIGIN_CHAIN_ID);
        console2.log("Hook address:      ", hookAddress);
        console2.log("Destination chain: ", DEST_CHAIN_ID);

        vm.startBroadcast(deployerKey);

        // Fund the RSC with lREACT so the service contract can debit subscription fees.
        // Each subscribe() call debits from the RSC's balance on the Reactive Network.
        // 3 subscriptions × 0.1 lREACT = 0.3 lREACT minimum.
        RangeMonitorRSC rsc = new RangeMonitorRSC{value: 0.3 ether}(
            hookAddress,
            ORIGIN_CHAIN_ID,
            DEST_CHAIN_ID
        );

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== RSC Deployment Complete ===");
        console2.log("RangeMonitorRSC: ", address(rsc));
        console2.log("");
        console2.log("Next: register RSC on the hook:");
        console2.log("  cast send $STABLE_STREAM_HOOK_ADDRESS");
        console2.log("    \"setReactiveContract(address)\"", address(rsc));
        console2.log("    --rpc-url $UNICHAIN_SEPOLIA_RPC --private-key $PRIVATE_KEY");
    }
}
