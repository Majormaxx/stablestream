# StableStream

> Automated yield routing for out-of-range concentrated USDC liquidity — powered by a Uniswap v4 Hook and a Reactive Network RSC running autonomously across two chains.

StableStream solves the **idle capital problem** in concentrated liquidity. When a stablecoin LP position falls out of range, USDC sits inert earning nothing. StableStream detects this in real time via the Uniswap v4 hook lifecycle, routes the idle capital to Compound V3, and recalls it **just-in-time** before the next swap — fully automated through a [Reactive Smart Contract](https://dev.reactive.network/) on the Reactive Network with zero off-chain infrastructure.

---

## Live Deployment

| Contract | Chain | Address |
|---|---|---|
| `StableStreamHook` | Unichain Sepolia (1301) | [`0xDB23B8Ff772fC1e29EB35a4BECe17f6D1a9A86C0`](https://sepolia.uniscan.xyz/address/0xDB23B8Ff772fC1e29EB35a4BECe17f6D1a9A86C0) |
| `YieldRouter` | Unichain Sepolia (1301) | [`0xc69a63B6FbB684f1aC47BDe6613ed49B66A9feeA`](https://sepolia.uniscan.xyz/address/0xc69a63B6FbB684f1aC47BDe6613ed49B66A9feeA) |
| `CompoundV3Adapter` | Unichain Sepolia (1301) | [`0x67fD183808Dc4B886b20946456F3fD81f488D2d7`](https://sepolia.uniscan.xyz/address/0x67fD183808Dc4B886b20946456F3fD81f488D2d7) |
| `StableStreamNFT` | Unichain Sepolia (1301) | [`0x6f265EB778C44118cfc8484cA44A2Ea216ea998C`](https://sepolia.uniscan.xyz/address/0x6f265EB778C44118cfc8484cA44A2Ea216ea998C) |
| `RangeMonitorRSC` | **Reactive Network — Lasna (5318007)** | [`0xa86591459C15d12F13AbaDf0d78Ec56F3e920a80`](https://lasna.reactscan.net/address/0xa86591459C15d12F13AbaDf0d78Ec56F3e920a80) |

**Frontend:** https://stablestream.vercel.app

---

## The Problem

Concentrated liquidity is capital-efficient when in range — and completely idle when out of range. For stablecoin pairs this is particularly wasteful: a tight USDC position can go out of range for hours or days with no mechanism to put that capital to work.

Standard mitigations require active LP monitoring or centralised keeper bots. StableStream replaces both with an autonomous, on-chain event-driven system.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                   Unichain Sepolia (1301)                    │
│                                                              │
│   LP                                                         │
│    │  deposit(usdc, tickLower, tickUpper)                    │
│    ▼                                                         │
│  StableStreamHook ─ afterAddLiquidity ──► mint NFT receipt   │
│         │                                                    │
│         │  afterSwap()  ─ tick crossed out of range         │
│         │               ─ emit PositionLeftRange(id, tick)  │
│         │                                                    │
│         │  beforeSwap() ─ tick re-entering range            │
│         │               ─ emit PositionEnteredRange(id)     │
│         │                                                    │
│         │◄── routeToYield(positionId) ─────────────────┐    │
│         │◄── recallFromYield(positionId) ──────────┐   │    │
└─────────┼──────────────────────────────────────────│───│────┘
          │        callbacks (Unichain Sepolia)       │   │
          │                                           │   │
┌─────────┼───────────────────────────────────────────┼───┼────┐
│         │   Reactive Network — Lasna (5318007)       │   │   │
│                                                      │   │   │
│      RangeMonitorRSC                                 │   │   │
│         ├── subscribes → PositionLeftRange ──────────┘   │   │
│         ├── subscribes → PositionEnteredRange ───────────┘   │
│         ├── rate limit: MAX_CALLBACKS_PER_BLOCK              │
│         ├── per-position cooldown: POSITION_COOLDOWN_BLOCKS  │
│         └── overflow queue: flushQueue()                     │
└──────────────────────────────────────────────────────────────┘
          │
          ▼  routeToYield / recallFromYield
       YieldRouter
          ├── APYVerifier   (TWAP anomaly detection)
          ├── RiskEngine    (risk-weighted source selection)
          └── CompoundV3Adapter ──► Compound V3 Comet (USDC)
```

### Position Lifecycle

| Step | Trigger | Actor |
|---|---|---|
| 1. Deposit | `deposit(amount, tickLower, tickUpper)` | LP |
| 2. NFT minted | `afterAddLiquidity` → `StableStreamNFT.mint()` | Hook |
| 3. Price exits range | `afterSwap` emits `PositionLeftRange` | Hook |
| 4. Capital routed | RSC calls `routeToYield` → USDC → Compound V3 | RSC → Hook |
| 5. Price re-enters | `beforeSwap` emits `PositionEnteredRange` | Hook |
| 6. JIT recall | RSC calls `recallFromYield` → USDC back to pool | RSC → Hook |
| 7. Withdraw | `withdraw(positionId)` → capital + yield | LP |

---

## Reactive Network Integration

This is the protocol's core technical differentiator. The Reactive Network enables **event-driven cross-chain automation** with no off-chain infrastructure.

### How it works

`RangeMonitorRSC` is deployed on **Reactive Network Lasna (chain ID 5318007)**. It holds three live subscriptions against `StableStreamHook` on Unichain Sepolia:

```solidity
// Subscribed event topics (registered in constructor via ISystemContract)
keccak256("PositionLeftRange(bytes32,int24)")      → routeToYield callback
keccak256("PositionEnteredRange(bytes32,int24)")   → recallFromYield callback (JIT)
keccak256("CapitalRouted(bytes32,address,uint256)") → observational only
```

When a subscribed event fires on Unichain Sepolia, Reactive Network nodes call `react(LogRecord)` on the RSC. The RSC emits a `Callback` event that instructs the network to submit a transaction on Unichain Sepolia:

```solidity
function react(LogRecord calldata log) external vmOnly {
    if (log.topic_0 == TOPIC_POSITION_LEFT_RANGE) {
        _handlePositionLeftRange(log.topic_1, log.block_number);
    } else if (log.topic_0 == TOPIC_POSITION_ENTERED_RANGE) {
        _handlePositionEnteredRange(log.topic_1, log.block_number);
    }
}

function _emitRouteToYield(bytes32 positionId) internal {
    emit Callback(
        DESTINATION_CHAIN_ID,  // Unichain Sepolia: 1301
        callbackTarget,        // StableStreamHook address
        CALLBACK_GAS_LIMIT,    // 300,000
        abi.encodeWithSignature("routeToYield(bytes32)", positionId)
    );
}
```

### Rate limiting and safety

Two configurable parameters protect against gas exhaustion and position thrashing:

| Parameter | Default | Setter |
|---|---|---|
| `MAX_CALLBACKS_PER_BLOCK` | 5 | `setMaxCallbacksPerBlock(uint256)` |
| `POSITION_COOLDOWN_BLOCKS` | 10 | `setPositionCooldownBlocks(uint256)` |

Positions exceeding the per-block cap are pushed to an overflow queue and drained via `flushQueue(maxCount)`. JIT recall (`recallFromYield`) bypasses all rate limits — capital must arrive before the swap executes.

### Deployment note

The RSC **cannot** be deployed via `forge create` or `forge script`. The Reactive Network's system precompiles revert during simulation. Deployment requires raw bytecode via `cast send --create`:

```bash
BYTECODE=$(cat out/RangeMonitorRSC.sol/RangeMonitorRSC.json | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['bytecode']['object'])")

ARGS=$(cast abi-encode "constructor(address,address,uint256)" \
  $HOOK_ADDRESS $OWNER_ADDRESS $ORIGIN_CHAIN_ID)

cast send \
  --rpc-url https://lasna-rpc.rnk.dev/ \
  --private-key $PRIVATE_KEY \
  --value "0.3ether" \
  --create "${BYTECODE}${ARGS#0x}"
```

The `0.3 ETH` covers gas for outbound callbacks to Unichain Sepolia. Successful deployment confirms 3 subscription logs in the transaction receipt.

---

## Unichain Integration

StableStream is deployed natively on **Unichain Sepolia** and uses Uniswap v4 primitives throughout.

### Hook permissions

The hook address is mined via CREATE2 so its lower 14 bits encode the required permission flags — a Uniswap v4 requirement.

```solidity
function getHookPermissions() public pure returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
        afterAddLiquidity:     true,  // mint NFT, record position
        beforeRemoveLiquidity: true,  // block direct removal of managed positions
        beforeSwap:            true,  // JIT recall signal + dynamic fee
        afterSwap:             true,  // detect range crossings
        // all others: false
    });
}
```

### PoolManager unlock pattern

All liquidity operations go through the v4 `PoolManager.unlock()` mechanism for atomic delta accounting:

```solidity
poolManager.unlock(abi.encode(ActionType.DEPOSIT, abi.encode(params)));
// PoolManager calls back → _unlockCallback → _handleDeposit
// Native ETH:  poolManager.settle{value: amount}()
// ERC-20:      sync → safeTransfer → settle()
```

### Dynamic fees

`DynamicFeeModule` computes swap fees that scale with the fraction of pool capital currently deployed to yield sources — compensating LPs for reduced swap availability:

```
fee = BASE_FEE + (YIELD_PREMIUM × yieldRatio)
```

Returned from `beforeSwap` using `LPFeeLibrary.DYNAMIC_FEE_FLAG`.

### EIP-1153 transient storage

The `pendingRecall` flag uses `TSTORE`/`TLOAD` (EIP-1153) instead of a persistent mapping — saving ~22,000 gas per flag versus cold `SSTORE`. The RSC's per-position cooldown provides cross-transaction idempotency.

### Pool configuration

| Parameter | Value |
|---|---|
| Chain | Unichain Sepolia (1301) |
| Token0 | ETH (native — `address(0)`) |
| Token1 | USDC `0x31d0220469e10c4E71834a79b1f276d740d3768F` |
| Fee tier | Dynamic (`DYNAMIC_FEE_FLAG`) |
| Tick spacing | 10 |
| Initial sqrtPrice | 2^96 (tick = 0) |
| Pool ID | `0x2af851d6f565ece7e573e814a3c453b0f75b4f56a55307e6dffdc0f91bb3ebed` |

---

## Contract Reference

### StableStreamHook

The central contract. Implements `IHooks` and acts as a delegated position manager.

| Function | Description |
|---|---|
| `deposit(amount, tickLower, tickUpper)` | Add USDC as concentrated liquidity; mint NFT receipt |
| `withdraw(positionId)` | Remove liquidity + accrued yield; burn NFT |
| `routeToYield(positionId)` | RSC-triggered — remove idle liquidity → Compound V3 |
| `recallFromYield(positionId)` | RSC-triggered — Compound V3 → re-add to pool (JIT) |
| `setReactiveContract(rsc)` | Owner — register the Reactive Network RSC address |
| `getDynamicFee(poolId)` | View — current computed swap fee |
| `isPendingRecall(positionId)` | View — EIP-1153 transient JIT flag |

### YieldRouter

Routes USDC to the highest risk-adjusted yield source from up to 8 registered adapters.

| Feature | Detail |
|---|---|
| Multi-source routing | Fixed array, `MAX_SOURCES = 8`, O(n) APY scan per routing decision |
| APY anomaly detection | `APYVerifier` — rolling TWAP; rejects sources reporting > 2× trailing average |
| Risk-weighted selection | `RiskEngine` — owner-assigned risk scores, LP-configurable tolerance |
| Emergency exit | `withdrawAll()` — drains all capital from active source in one tx |

### RangeMonitorRSC

Deployed on Reactive Network Lasna. Monitors StableStreamHook and dispatches autonomous callbacks.

| Feature | Detail |
|---|---|
| Subscriptions | 3 event topics on `StableStreamHook` |
| Rate limiting | Per-block cap + per-position cooldown |
| Overflow queue | `bytes32[]` FIFO, drained via `flushQueue(maxCount)` |
| JIT bypass | `recallFromYield` skips rate limit — capital must arrive before swap |
| Owner controls | `rnOnly` modifier — callable as a regular tx on Reactive Network |

### Adapters

| Adapter | Protocol | Notes |
|---|---|---|
| `CompoundV3Adapter` | Compound V3 Comet | USDC market; `setMockAPY(bps)` for testnet use |
| `AaveV3Adapter` | Aave V3 | Ready; not yet live on Unichain Sepolia |
| `NativeStakeAdapter` | ETH native staking | For native ETH yield routing |

---

## Repository Structure

```
src/
├── StableStreamHook.sol        # Uniswap v4 hook — core protocol logic
├── YieldRouter.sol             # Multi-source yield routing with APY ranking
├── StableStreamNFT.sol         # ERC-721 position receipt tokens
├── DynamicFeeModule.sol        # Yield-ratio-scaled swap fees
├── adapters/
│   ├── CompoundV3Adapter.sol   # Compound V3 Comet integration
│   ├── AaveV3Adapter.sol       # Aave V3 integration
│   └── NativeStakeAdapter.sol  # Native ETH staking
├── libraries/
│   ├── RangeCalculator.sol     # Tick math and range detection
│   ├── YieldAccounting.sol     # Per-position yield tracking
│   ├── APYVerifier.sol         # TWAP anomaly detection
│   ├── RiskEngine.sol          # Risk-weighted source scoring
│   └── TransientStorage.sol    # EIP-1153 TSTORE/TLOAD wrapper
├── reactive/
│   └── RangeMonitorRSC.sol     # Reactive Network automation contract
└── interfaces/

script/
├── Deploy.s.sol                # Full protocol deployment (Unichain Sepolia)
├── DeployRSC.s.sol             # RSC deployment (Lasna — use cast send --create)
└── InitPool.s.sol              # Pool initialisation

test/                           # 181 Foundry test cases across 10 suites
frontend/                       # Next.js + wagmi + viem interface
```

---

## Running Tests

```bash
forge test
```

10 test suites, 181 test cases covering hook permissions, range logic, yield routing, NFT positions, dynamic fees, risk engine, APY verification, transient storage, multi-token support, and security edge cases.

```bash
forge test --match-contract SecurityEdgeCases -vvv   # reentrancy, access control
forge test --match-contract Integration -vvv         # full lifecycle
forge test --match-contract DynamicFee -vvv          # fee scaling with yield ratio
```

---

## Local Development

**Prerequisites:** Foundry, Node.js 18+

```bash
git clone <repo> --recurse-submodules
cd stablestream
forge install
forge build
forge test

# Deploy to Unichain Sepolia
cp .env.example .env   # set PRIVATE_KEY
forge script script/Deploy.s.sol:DeployStableStream \
  --rpc-url https://sepolia.unichain.org \
  --broadcast -vvvv

# Deploy RSC to Reactive Network (cast send --create required)
# See script/DeployRSC.s.sol for the full cast command
```

**Frontend:**

```bash
cd frontend && npm install && npm run dev
# http://localhost:3000
```

---

## Why Reactive Network

The automation requirement here is **reactive, not scheduled**. A keeper with a cron job would either poll too frequently (wasting gas) or too slowly (leaving capital idle). An RSC fires within the same block as the triggering event — on Unichain's 1-second block times that means JIT recall can complete in the same second that `beforeSwap` detects a range re-entry.

The integration follows the canonical two-contract Reactive Network pattern:

1. **Reactive Network (Lasna):** `RangeMonitorRSC` — subscribes to events, applies rate limits, emits `Callback`
2. **Destination chain (Unichain Sepolia):** `StableStreamHook` — exposes `routeToYield` / `recallFromYield` gated by `onlyReactive`

StableStream has **zero off-chain dependencies** — no bots, no oracles, no centralised relayers.

---

## Hackathon Track

Built for the **Uniswap Hookathon** with the **Reactive Network prize track**.

- **Automated Liquidity Provisioning** — RSC-driven rebalancing of concentrated USDC positions to yield
- **Asynchronous Swap Hooks** — cross-chain event → callback pattern enabling JIT capital recall
- **Liquidity Optimizations** — idle capital earns yield between range crossings with no LP action required

---

## License

MIT
