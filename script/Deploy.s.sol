// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

import {StableStreamHook} from "../src/StableStreamHook.sol";
import {StableStreamNFT} from "../src/StableStreamNFT.sol";
import {YieldRouter} from "../src/YieldRouter.sol";
import {CompoundV3Adapter} from "../src/adapters/CompoundV3Adapter.sol";

/// @title DeployStableStream
/// @notice Deploys the full StableStream protocol to Unichain Sepolia (chain ID 1301).
///
/// @dev    Deployment order:
///           1. YieldRouter
///           2. CompoundV3Adapter (sole yield source — Aave V3 not yet on Unichain Sepolia)
///           3. Mine a CREATE2 salt so StableStreamHook lands at an address
///              whose lower 14 bits match the required hook permission flags.
///           4. StableStreamHook (at the mined address)
///           5. StableStreamNFT
///           6. Wire everything together
///
///         Run with:
///           forge script script/Deploy.s.sol:DeployStableStream \
///             --rpc-url https://sepolia.unichain.org \
///             --broadcast \
///             --verify \
///             --etherscan-api-key $ETHERSCAN_API_KEY \
///             -vvvv
///
/// @custom:chain  Unichain Sepolia — chain ID 1301
contract DeployStableStream is Script {
    // -------------------------------------------------------------------------
    // Unichain Sepolia verified addresses
    // -------------------------------------------------------------------------

    address constant POOL_MANAGER   = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address constant USDC           = 0x31d0220469e10c4E71834a79b1f276d740d3768F;
    address constant COMPOUND_COMET = 0x2a02b9a5C58a67Cf695fd1d92D18d56FDfBbc40E;

    // -------------------------------------------------------------------------
    // Hook permission flags (must match StableStreamHook.getHookPermissions())
    // -------------------------------------------------------------------------

    // afterAddLiquidity      = 1 << 10 = 0x0400
    // beforeRemoveLiquidity  = 1 << 9  = 0x0200
    // beforeSwap             = 1 << 7  = 0x0080
    // afterSwap              = 1 << 6  = 0x0040
    uint160 constant HOOK_FLAGS =
        Hooks.AFTER_ADD_LIQUIDITY_FLAG |
        Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
        Hooks.BEFORE_SWAP_FLAG |
        Hooks.AFTER_SWAP_FLAG;

    // -------------------------------------------------------------------------
    // Main
    // -------------------------------------------------------------------------

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console2.log("=== StableStream Deployment ===");
        console2.log("Deployer:     ", deployer);
        console2.log("Chain ID:     ", block.chainid);
        console2.log("PoolManager:  ", POOL_MANAGER);
        console2.log("USDC:         ", USDC);

        vm.startBroadcast(deployerKey);

        // ── 1. YieldRouter ────────────────────────────────────────────────────
        YieldRouter yieldRouter = new YieldRouter(USDC, deployer);
        console2.log("YieldRouter:  ", address(yieldRouter));

        // ── 2. CompoundV3Adapter ──────────────────────────────────────────────
        // Aave V3 is not yet deployed on Unichain Sepolia — Compound only for now
        CompoundV3Adapter compoundAdapter = new CompoundV3Adapter(
            COMPOUND_COMET,
            USDC,
            deployer
        );
        console2.log("CompoundAdapter:", address(compoundAdapter));

        // ── 3. Mine CREATE2 salt for hook address with correct permission bits ─
        bytes memory hookCreationCode = abi.encodePacked(
            type(StableStreamHook).creationCode,
            abi.encode(
                IPoolManager(POOL_MANAGER),
                yieldRouter,
                USDC,
                deployer
            )
        );

        // Foundry routes `new Contract{salt: s}()` through its deterministic CREATE2 factory
        address foundryCreate2Factory = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

        bytes32 salt;
        address hookAddress;
        for (uint256 i = 0; i < 160_000; i++) {
            salt = bytes32(i);
            hookAddress = _computeCreate2Address(foundryCreate2Factory, salt, keccak256(hookCreationCode));
            if (uint160(hookAddress) & 0x3FFF == uint160(HOOK_FLAGS)) break;
        }
        console2.log("Mined hook address:", hookAddress);
        console2.log("CREATE2 salt (uint):", uint256(salt));

        // ── 4. Deploy StableStreamHook at the mined address ───────────────────
        StableStreamHook hook = new StableStreamHook{salt: salt}(
            IPoolManager(POOL_MANAGER),
            yieldRouter,
            USDC,
            deployer
        );
        require(address(hook) == hookAddress, "Hook address mismatch - re-mine salt");
        console2.log("StableStreamHook:", address(hook));

        // ── 5. Deploy StableStreamNFT ─────────────────────────────────────────
        StableStreamNFT nft = new StableStreamNFT(address(hook));
        console2.log("StableStreamNFT: ", address(nft));

        // ── 6. Wire everything together ───────────────────────────────────────

        // Register Compound adapter in YieldRouter
        yieldRouter.registerSource(address(compoundAdapter));

        // Seed APY snapshot (Compound ~2.5% on Unichain Sepolia)
        yieldRouter.initializeAPYSnapshot(address(compoundAdapter), 250);

        // Authorise hook to call YieldRouter
        yieldRouter.setAuthorizedCaller(address(hook));

        // Register NFT in hook
        hook.setNFT(nft);

        // Note: RSC address is registered separately after Reactive Network deployment
        // hook.setReactiveContract(<RSC_ADDRESS>);

        vm.stopBroadcast();

        // ── Summary ───────────────────────────────────────────────────────────
        console2.log("");
        console2.log("=== Deployment Complete ===");
        console2.log("YieldRouter:     ", address(yieldRouter));
        console2.log("CompoundAdapter: ", address(compoundAdapter));
        console2.log("StableStreamHook:", address(hook));
        console2.log("StableStreamNFT: ", address(nft));
        console2.log("");
        console2.log("Next steps:");
        console2.log("  1. Deploy RangeMonitorRSC on Reactive Network (Kopli testnet)");
        console2.log("  2. Call hook.setReactiveContract(<RSC_ADDRESS>)");
        console2.log("  3. Initialize a USDC/USDT pool on Uniswap v4 using this hook");
        console2.log("  4. Verify contracts on Uniscan");
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Computes the CREATE2 address without deploying anything.
    function _computeCreate2Address(
        address deployer_,
        bytes32 salt_,
        bytes32 initCodeHash
    ) internal pure returns (address) {
        return address(uint160(uint256(
            keccak256(abi.encodePacked(bytes1(0xff), deployer_, salt_, initCodeHash))
        )));
    }
}
