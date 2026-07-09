// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/// @title InitPool
/// @notice Initializes a USDC/ETH pool on Uniswap v4 (Unichain Sepolia) using StableStreamHook.
///
///         Run with:
///           forge script script/InitPool.s.sol:InitPool \
///             --rpc-url $UNICHAIN_SEPOLIA_RPC \
///             --broadcast \
///             -vvvv
///
/// @custom:chain Unichain Sepolia — chain ID 1301
contract InitPool is Script {

    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;

    // USDC on Unichain Sepolia
    address constant USDC = 0x31d0220469e10c4E71834a79b1f276d740d3768F;

    // ETH is represented as address(0) / Currency.wrap(address(0)) in v4
    address constant ETH  = address(0);

    // 0.05% fee tier — appropriate for stable/liquid pairs
    uint24 constant FEE = 500;

    // Tick spacing for 0.05% fee tier
    int24 constant TICK_SPACING = 10;

    // Fallback sqrt price for testnet demos only: tick 0 (1:1).
    // Production deployments MUST supply INITIAL_SQRT_PRICE_X96 via env var.
    // For 2300 USDC/ETH: tick ≈ -125000; compute with TickMath.getSqrtPriceAtTick(-125000).
    uint160 constant DEMO_SQRT_PRICE = 79228162514264337593543950336; // sqrtPriceX96 at tick 0 (1:1)

    function run() external {
        uint256 deployerKey  = vm.envUint("PRIVATE_KEY");
        address hookAddress  = vm.envAddress("STABLE_STREAM_HOOK_ADDRESS");

        // Read initial price from env; fall back to demo default only when not set.
        // Set INITIAL_SQRT_PRICE_X96 for any non-demo deployment to avoid initializing
        // at a 1:1 price that would be immediately arbitraged (Finding 8658afec).
        uint160 initialSqrtPrice;
        try vm.envUint("INITIAL_SQRT_PRICE_X96") returns (uint256 envPrice) {
            require(envPrice != 0 && envPrice <= type(uint160).max, "InitPool: invalid INITIAL_SQRT_PRICE_X96");
            initialSqrtPrice = uint160(envPrice);
        } catch {
            initialSqrtPrice = DEMO_SQRT_PRICE;
        }

        address deployer = vm.addr(deployerKey);

        console2.log("=== Initialize Uniswap v4 Pool ===");
        console2.log("Deployer:     ", deployer);
        console2.log("PoolManager:  ", POOL_MANAGER);
        console2.log("Hook:         ", hookAddress);
        console2.log("Token0 (ETH): ", ETH);
        console2.log("Token1 (USDC):", USDC);
        console2.log("Fee:          ", FEE);

        // currency0 must be < currency1 (address order)
        // ETH (address(0)) < USDC so currency0=ETH, currency1=USDC
        PoolKey memory key = PoolKey({
            currency0:   Currency.wrap(ETH),
            currency1:   Currency.wrap(USDC),
            fee:         FEE,
            tickSpacing: TICK_SPACING,
            hooks:       IHooks(hookAddress)
        });

        vm.startBroadcast(deployerKey);

        console2.log("InitialSqrtPrice:", initialSqrtPrice);
        IPoolManager(POOL_MANAGER).initialize(key, initialSqrtPrice);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Pool Initialized ===");
        console2.log("Pool key hash can be derived from the above parameters.");
        console2.log("Next: Add liquidity to the pool via a PositionManager.");
    }
}
