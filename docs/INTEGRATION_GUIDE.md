# Add Idle-Capital Yield Routing to Your Own v4 Hook

This guide shows how to add automatic idle-capital yield routing to a Uniswap v4 hook using `IdleCapitalYieldModule`. The complete integration is ~20 lines of Solidity.

## Prerequisites

1. Deploy a `YieldRouter` with at least one `IYieldSource` adapter (Compound, Aave, or your own).
2. Seed an APY snapshot so the router can select the best source.

## Step 1: Inherit the module

```solidity
import {IdleCapitalYieldModule} from "path/to/core/IdleCapitalYieldModule.sol";

contract MyHook is IdleCapitalYieldModule {
    constructor(IPoolManager pm, YieldRouter router, address asset, address owner)
        IdleCapitalYieldModule(pm, router, asset, owner)
    {}
}
```

That's it for the minimal case. The four hook callbacks (`afterAddLiquidity`, `beforeRemoveLiquidity`, `beforeSwap`, `afterSwap`), position tracking, yield routing, and JIT recall are inherited.

## Step 2: Deploy RangeMonitorRSC

Deploy a `RangeMonitorRSC` instance on Reactive Network pointed at your hook:

```solidity
RangeMonitorRSC rsc = new RangeMonitorRSC{value: 0.3 ether}(
    address(myHook), ORIGIN_CHAIN_ID, DEST_CHAIN_ID
);
myHook.setReactiveContract(address(rsc));
```

The RSC watches `PositionLeftRange`/`PositionEnteredRange` events and calls `routeToYield`/`recallFromYield` autonomously.

## Step 3: Wire the yield router

```solidity
yieldRouter.setAuthorizedCaller(address(myHook));
yieldRouter.initializeAPYSnapshot(address(compoundAdapter), 250);
```

## Step 4: Done

Users call `deposit(key, tickLower, tickUpper, amount)` to open a managed position. Capital is automatically routed to yield when out of range and recalled JIT before the next swap. No keeper bots, no cron jobs, no off-chain infrastructure.

## Customization

Override the virtual lifecycle hooks for product-specific behavior:

```solidity
function _onPositionOpened(bytes32 positionId, address owner) internal override {
    // Mint NFT, send notification, etc.
}
function _onPositionClosed(bytes32 positionId) internal override {
    // Burn NFT, settle, etc.
}
```

See `StableStreamHook` (`app/StableStreamHook.sol`) for a full production example with ERC-721 position receipts and multi-token whitelisting.

## Hook address mining

The module requires four permission flags: `afterAddLiquidity`, `beforeRemoveLiquidity`, `beforeSwap`, and `afterSwap`. If your hook needs additional callbacks, combine the flags and re-mine the address. See `app/script/Deploy.s.sol` for the CREATE2 salt-mining pattern.
