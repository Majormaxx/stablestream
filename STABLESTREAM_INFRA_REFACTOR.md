# StableStream → Idle-Capital Yield Module: End-to-End Refactor Spec

**Audience:** coding agent implementing this refactor
**Repo:** github.com/Majormaxx/stablestream (main branch, current state audited 2026-07-08)
**Goal:** turn StableStream from a single deployed product into a reusable Uniswap v4 hook module — `IdleCapitalYieldModule` — that any v4 hook developer can inherit from, wire up, and deploy against their own pool. StableStream itself becomes the reference implementation built on top of the module. This is being done to apply to Uniswap Foundation's Hook Design Lab, which funds public goods other hook builders can reuse — not standalone products.

Do not treat this as a rewrite. ~70% of the code is already correctly factored. The problem is one file, `src/StableStreamHook.sol` (1123 lines), which fuses the reusable routing primitive with StableStream-specific product logic (NFT receipts, position enumeration, multi-token whitelisting). The job is surgical extraction, not redesign.

---

## 0. Repo audit — what's already reusable vs. what's coupled

Read this section before touching anything. It tells you what to leave alone.

### Already reusable as-is (do not restructure, only re-export/re-package)

| File | Why it's already a primitive |
|---|---|
| `src/interfaces/IYieldSource.sol` | Clean adapter interface. Zero StableStream-specific assumptions. |
| `src/YieldRouter.sol` | Takes a single `authorizedCaller` (set post-deploy via `setAuthorizedCaller`), not hardcoded to `StableStreamHook`. Any hook can be the authorized caller. `MAX_SOURCES`-bounded array, APY anomaly detection (`APYVerifier`), risk filtering (`RiskEngine`) — all generic. |
| `src/adapters/AaveV3Adapter.sol`, `CompoundV3Adapter.sol`, `NativeStakeAdapter.sol` | Each implements `IYieldSource` only. No hook coupling. |
| `src/libraries/RiskEngine.sol`, `APYVerifier.sol` | Pure libraries, no storage, no coupling. |
| `src/libraries/RangeCalculator.sol` | Pure tick-range math (`crossedOutOfRange`, `crossedIntoRange`, `isInRange`). Generic to any concentrated-liquidity hook. |
| `src/libraries/TransientStorage.sol` | Generic EIP-1153 TSTORE/TLOAD helper, no StableStream-specific slots baked in beyond the prefix constant (which lives in the hook, correctly). |
| `src/libraries/YieldAccounting.sol` | Generic per-position yield bookkeeping struct + methods (`recordDeposit`, `recordWithdrawal`, `canRoute`). |
| `src/DynamicFeeModule.sol` | Pure library, pool-agnostic fee curve based on `(totalCapital, yieldCapital)`. Reusable by any hook that wants a yield-utilization-scaled fee, independent of what routes capital there. |
| `src/reactive/RangeMonitorRSC.sol` | Already parameterized: `HOOK_ADDRESS` is an immutable set in the constructor, not hardcoded. This is already a **deployable template** — any hook deployer instantiates their own copy pointed at their own hook. Confirm the event topics (`PositionLeftRange`, `PositionEnteredRange`) are declared as a documented interface requirement (see Section 3), not just "whatever StableStreamHook happens to emit." |

### The actual coupling problem

`src/StableStreamHook.sol` mixes four concerns in one 1123-line, one-inheritance-chain contract:

1. **The reusable primitive** (~55% of the file): `Action` enum, `TrackedPosition` struct core fields, `getHookPermissions()`, `beforeSwap`/`afterSwap` range-detection logic, `routeToYield`/`recallFromYield`, `_unlockCallback` dispatch + all four `_handle*` sub-handlers, `_settleDeltas`/`_settleCurrency`/`_takePositiveDeltas`, `ROUTE_COOLDOWN` + cooldown enforcement, `PENDING_RECALL_PREFIX` transient-storage pattern.
2. **Position lifecycle** (`deposit`, `withdraw`, `computePositionId`, `getOwnerPositions`, `getPosition`): mostly generic, but currently hardcoded to `usdc` as the single tracked asset per instance (multi-token support is bolted on via `whitelistedStables`/`tokenRouters` mappings that are never actually branched on inside `deposit`/`withdraw` — worth checking, see Section 4 Known Gap).
3. **StableStream-the-product specifics**: `StableStreamNFT` minting/burning (`setNFT`, `nft.mint`, `nft.burn`), `whitelistStablecoin`/`tokenRouters` multi-token admin surface.
4. **Fee logic wiring**: calling `DynamicFeeModule.computeFee` inside `beforeSwap` — this is fine to keep in the base, since it's itself a generic library call, not product-specific.

The fix: split (1) into a new abstract base contract. Keep (2)-(4) as StableStream's own subclass.

---

## 1. Target package structure

Restructure the repo into four logical packages inside the same monorepo (do not split into separate repos yet — that adds CI/release overhead you don't need for the Hook Design Lab application; separate repos can happen later if this gets traction):

```
stablestream/
├── src/
│   ├── core/                          # NEW — the reusable module (what Hook Design Lab is funding)
│   │   ├── IdleCapitalYieldModule.sol   # NEW — abstract base contract (extracted primitive)
│   │   ├── interfaces/
│   │   │   ├── IYieldSource.sol         # MOVED from src/interfaces/ (unchanged)
│   │   │   └── IIdleCapitalYieldModule.sol  # NEW — public interface other devs code against
│   │   ├── YieldRouter.sol              # MOVED from src/ (unchanged)
│   │   ├── adapters/                    # MOVED from src/adapters/ (unchanged)
│   │   ├── libraries/
│   │   │   ├── RangeCalculator.sol      # MOVED (unchanged)
│   │   │   ├── TransientStorage.sol     # MOVED (unchanged)
│   │   │   ├── YieldAccounting.sol      # MOVED (unchanged)
│   │   │   ├── RiskEngine.sol           # MOVED (unchanged)
│   │   │   ├── APYVerifier.sol          # MOVED (unchanged)
│   │   │   └── DynamicFeeModule.sol     # MOVED (unchanged)
│   │   └── reactive/
│   │       └── RangeMonitorRSC.sol      # MOVED (unchanged) — the deployable RSC template
│   │
│   └── reference/                      # RENAMED from top-level src/ — StableStream itself
│       ├── StableStreamHook.sol         # SLIMMED — now inherits IdleCapitalYieldModule
│       ├── StableStreamNFT.sol          # UNCHANGED
│       └── script/                      # MOVED from top-level script/
│
├── test/
│   ├── core/                           # NEW — tests against a MINIMAL hook, proving reusability
│   │   └── MinimalHook.t.sol            # NEW — see Section 5
│   └── reference/                      # MOVED — existing StableStreamHook tests (all 181, unchanged)
│
├── docs/
│   └── INTEGRATION_GUIDE.md            # NEW — "add this to your own hook in ~50 lines" (Section 6)
│
└── frontend/                            # UNCHANGED, but reframed in README as "reference dApp," not "the product"
```

**Why keep it in one repo:** Hook Design Lab evaluates the artifact and the docs, not your folder topology. A monorepo with a clearly separated `src/core/` is enough evidence of "this is a module," and it means you don't have to solve cross-repo versioning under a July 10 deadline.

---

## 2. `IdleCapitalYieldModule.sol` — the extraction, function by function

This is the core deliverable. Create `src/core/IdleCapitalYieldModule.sol` as an **abstract contract** that `StableStreamHook` will inherit from. Move the following out of `StableStreamHook.sol` verbatim (logic unchanged — this is extraction, not rewriting business logic), making the product-specific hooks `virtual`/overridable where noted.

### 2.1 Move as-is (no behavior change)

- `enum Action { DEPOSIT, WITHDRAW, ROUTE_TO_YIELD, RECALL_FROM_YIELD }`
- Constants: `ROUTE_COOLDOWN`, `PENDING_RECALL_PREFIX`
- Errors: `PositionNotFound`, `PositionAlreadyClosed`, `PositionCurrentlyInRange`, `PositionAlreadyRouted`, `PositionNotRouted`, `RoutingCooldownActive`, `UnauthorizedRoutingCaller`, `ZeroAmount`, `CapitalInYield`
- Events: `PositionLeftRange`, `PositionEnteredRange`, `CapitalRouted`, `CapitalRecalled`
- `getHookPermissions()` — unchanged, this permission set (`afterAddLiquidity`, `beforeRemoveLiquidity`, `beforeSwap`, `afterSwap`) is exactly the module's contract with `IHooks`, not a StableStream choice.
- `beforeSwap()` — full body, including the dynamic-fee branch (keep `DynamicFeeModule` call here; it's generic).
- `afterSwap()` — full body (the tick-scan loop over `_poolPositionIds[pid]`).
- `routeToYield()` — full body.
- `recallFromYield()` — full body.
- `_unlockCallback()` dispatcher and all four `_handle*` sub-handlers (`_handleDeposit`, `_handleWithdraw`, `_handleRouteToYield`, `_handleRecallFromYield`) — including the Case A/B/C liquidity-math branches and their documented bug-fix comments (Finding 9830b75d, Finding 6a3185ad, Finding 222157ab — **preserve these comments verbatim**, they're evidence of real security review, which Hook Design Lab will value).
- `_settleDeltas`, `_settleCurrency`, `_takePositiveDeltas` — unchanged.
- `_poolCapitalSnapshot`, `_removeFromPoolPositionIds` — unchanged.
- `_positionId()` — unchanged.
- State: `positions`, `_poolPositionIds`, `_prevTicks`, `poolTotalCapital`, `poolYieldCapital`, `reactiveContract`.
- `TrackedPosition` struct — keep all current fields (`owner`, `asset`, `poolId`, `tickLower`, `tickUpper`, `liquidity`, `yieldDeposited`, `activeYieldSource`, `yieldState`, `closed`, `key`). Do not add product fields here.
- `setReactiveContract()` — unchanged.
- `isPendingRecall()`, `getDynamicFee()` — unchanged.

### 2.2 Turn into extension points (`virtual` hooks called from the moved logic)

Two places in the current code touch product-specific state. Replace the direct calls with `virtual internal` hooks that default to a no-op, so a bare-bones consumer doesn't have to implement anything, but `StableStreamHook` overrides them to keep NFT behavior identical.

- In `deposit()` (stays in `StableStreamHook`, see 2.3) — after registering the position, instead of directly calling `nft.mint(msg.sender, positionId)`, the base's position-registration path should call a `virtual internal function _onPositionOpened(bytes32 positionId, address owner) virtual internal {}` hook. `StableStreamHook` overrides it to mint the NFT.
- Same pattern for position closure: `_onPositionClosed(bytes32 positionId) virtual internal {}`, overridden in `StableStreamHook` to burn the NFT. Call sites: end of `withdraw()`, and the early-return branch inside `routeToYield()` when `recovered == 0`.

This is the only actual behavioral abstraction needed. Everything else is a straight cut-and-paste move.

### 2.3 Stays in `StableStreamHook.sol` (the "reference implementation" layer)

- `deposit()` — but its body now calls the base's internal position-registration helper (extract the shared tail of `deposit()` — building `TrackedPosition`, pushing to `ownerPositions`/`_poolPositionIds`, calling `_poolCapitalSnapshot`, emitting `PositionOpened` — into a `_registerPosition(...)` internal function in the base, since none of that is product-specific either. Only the NFT mint call and `PositionOpened` event's product-facing metadata, if any, stay product-side via the `_onPositionOpened` hook).
- `withdraw()` — same treatment; the recall + liquidity-removal + settlement logic moves to the base as a `_closePosition(...)` internal helper; `withdraw()` in `StableStreamHook` becomes a thin wrapper that checks ownership, calls `_closePosition`, and the NFT burn happens via `_onPositionClosed`.
- `whitelistStablecoin()`, `tokenRouters`, `whitelistedStables` — StableStream-specific multi-token admin surface. Stays.
- `setNFT()`, `nft` state var, `StableStreamNFT` import — stays.
- `getOwnerPositions()`, `getPosition()`, `computePositionId()` — these are generic enough to live in the base too (they're pure state readers over `positions`/`ownerPositions`, which live in the base). Move them to the base; `StableStreamHook` inherits them for free. This is a case where "stays in StableStreamHook" isn't right — move these two view functions to `IdleCapitalYieldModule`.

### 2.4 Constructor split

`IdleCapitalYieldModule`'s constructor takes `(IPoolManager, YieldRouter, address asset, address owner)` — exactly today's `StableStreamHook` constructor minus the NFT/multi-token pre-whitelisting. `StableStreamHook`'s constructor calls `super(...)` then does its own `whitelistedStables[_usdc] = true; tokenRouters[_usdc] = address(_yieldRouter);` — this part is legitimately product-specific (multi-stablecoin support wasn't in the base's `TrackedPosition.asset` design as a first-class multi-router concept) and should stay in `StableStreamHook`.

---

## 3. `IIdleCapitalYieldModule.sol` — the public interface

Create a minimal interface file that captures the **contract with the outside world** — this is the artifact a hook developer reads first to decide whether to integrate, and what an RSC deployer needs to know to point `RangeMonitorRSC` at a new hook:

- Event signatures: `PositionLeftRange(bytes32,int24)`, `PositionEnteredRange(bytes32,int24)`, `CapitalRouted(bytes32,address,uint256)`, `CapitalRecalled(bytes32,address,uint256,uint128)`.
- External function signatures: `routeToYield(bytes32)`, `recallFromYield(bytes32)`, `setReactiveContract(address)`, `getPosition(bytes32)`, `computePositionId(...)`.

This file is what makes `RangeMonitorRSC.sol`'s event-topic constants (`TOPIC_POSITION_LEFT_RANGE`, etc.) a documented dependency instead of an implicit assumption — cite this interface in the RSC's NatSpec header.

---

## 4. Known gap to fix (or explicitly scope out) before the application

`whitelistedStables`/`tokenRouters` exist on `StableStreamHook` but grep the current `deposit()`/`withdraw()` bodies — they reference `usdc` directly (the single immutable), not `tokenRouters[token]` for an arbitrary whitelisted token. Multi-token support is currently **admin-configurable but not actually wired into the deposit/withdraw/route paths**. Two options:

- **(A) Scope it out explicitly.** State in the application and `INTEGRATION_GUIDE.md` that v1 of the module is single-asset-per-instance (matches `YieldRouter`'s single `immutable asset` design anyway), and multi-asset support is a listed roadmap item. This is the honest option and costs zero engineering time before July 10.
- **(B) Fix it for real** by making `IdleCapitalYieldModule` generic over `asset` per-position (using `TrackedPosition.asset` which already exists) and routing through `tokenRouters[pos.asset]` instead of the single `usdc` immutable. This is a real, moderate-sized change (touches `deposit`, `withdraw`, `routeToYield`, `recallFromYield`, and `YieldRouter` selection) and risks breaking the 181 passing tests close to the deadline.

**Recommendation: do (A).** Don't attempt (B) before July 10. A module that's honestly single-asset and well-documented beats a rushed multi-asset change that breaks tests three days before a deadline. Note it as roadmap in the application.

---

## 5. Proving reusability: `test/core/MinimalHook.t.sol`

This is the single highest-leverage artifact for the application. Write a **new, separate, minimal hook contract** (in the test folder, not shipped as a product) that does nothing except inherit `IdleCapitalYieldModule` and implement the bare minimum to compile:

```solidity
// test/core/MinimalHook.sol — a from-scratch hook builder would write this
contract MinimalHook is IdleCapitalYieldModule {
    constructor(IPoolManager pm, YieldRouter router, address asset, address owner)
        IdleCapitalYieldModule(pm, router, asset, owner)
    {}
    // That's it. No NFT, no multi-token, no frontend.
}
```

Then write `MinimalHook.t.sol` with a handful of tests (deposit → afterSwap detects range exit → routeToYield → afterSwap detects range entry → recallFromYield → withdraw) using this bare contract instead of `StableStreamHook`. If these tests pass, you have concrete proof — not marketing language — that the module works independent of StableStream's product layer. Screenshot or link this test file directly in the Hook Design Lab application; it's worth more than any amount of prose about "reusability."

---

## 6. `docs/INTEGRATION_GUIDE.md` — required deliverable

Write a short guide, target ~50-80 lines of actual Solidity, titled something like "Add idle-capital yield routing to your own v4 hook." Structure:

1. Prerequisites: deploy a `YieldRouter`, register at least one `IYieldSource` adapter (point to existing Aave/Compound adapters or bring your own), seed an APY snapshot.
2. Inherit `IdleCapitalYieldModule` in your hook, implement `getHookPermissions()` if you need additional callbacks beyond the four the module declares (note: v4 hook addresses are permission-mined, so combining the module's four callbacks with your own hook's callbacks requires re-mining the address — flag this explicitly, it's the one real integration cost).
3. Deploy your own `RangeMonitorRSC` instance on Reactive Network pointed at your hook's address (cite `IIdleCapitalYieldModule`'s event signatures as the contract it depends on).
4. Call `setReactiveContract()` on your hook once the RSC is deployed.
5. Done — `deposit`/`withdraw` (or your own equivalents calling the inherited internals) now get automatic idle-capital routing.

If you can't get the actual worked example under ~80 lines using `MinimalHook.sol` as the base, that's a signal the extraction in Section 2 isn't clean yet — go back and cut further before treating the doc as done.

---

## 7. Sequencing for the agent (do in this order, verify tests pass after each step)

1. Create `src/core/` and `src/reference/` folders. Move files per Section 1 with `git mv` (preserve history) — no code changes yet. Update all import paths across the repo (contracts, scripts, tests) to match new locations. **Run full test suite — should pass unchanged**, since nothing but paths moved.
2. Create `src/core/IdleCapitalYieldModule.sol`. Cut (not copy) the elements listed in Section 2.1 out of `StableStreamHook.sol` into it, converting free functions/state into an `abstract contract`. Add the two `virtual internal` hooks from Section 2.2 as no-op stubs.
3. Update `StableStreamHook.sol` to `is IdleCapitalYieldModule`, remove now-duplicated state/logic, override `_onPositionOpened`/`_onPositionClosed` with the NFT mint/burn calls, adjust constructor to call `super(...)`. **Run full test suite — must still pass, all 181 tests, unchanged behavior.** If anything fails, the extraction introduced a behavior change — find it and fix it before proceeding; do not touch test files to make them pass.
4. Move `getOwnerPositions`, `getPosition`, `computePositionId` to the base per Section 2.3.
5. Create `IIdleCapitalYieldModule.sol` per Section 3. Add its import/reference to `RangeMonitorRSC.sol`'s NatSpec (comment only, no logic change).
6. Write `test/core/MinimalHook.sol` + `MinimalHook.t.sol` per Section 5. This is new code, not a refactor of existing tests — write it fresh, keep it deliberately minimal.
7. Write `docs/INTEGRATION_GUIDE.md` per Section 6, using the actual `MinimalHook.sol` as the worked example so the doc and the test can't drift apart.
8. Update top-level `README.md`: reframe the opening section as "StableStream is built on IdleCapitalYieldModule, a reusable idle-capital-to-yield primitive for Uniswap v4 hooks" with a link to `docs/INTEGRATION_GUIDE.md`, and move the current product pitch (NFT receipts, frontend, StableStream-specific APY numbers) below the fold as "reference implementation." Do not delete the product framing — Hook Design Lab still wants to see a working, tested application of the primitive, just not as the headline.
9. Full test run + `forge coverage` sanity check that nothing regressed. Confirm `MinimalHook.t.sol` passes.
10. Do not attempt Section 4 option (B) unless steps 1-9 finish with time to spare before July 10.

---

## 8. What this buys you for the Hook Design Lab application

- A named, interface-documented module (`IdleCapitalYieldModule` / `IIdleCapitalYieldModule`) instead of a monolithic product contract.
- A passing test suite proving the module works independent of StableStream (`MinimalHook.t.sol`) — the single most convincing artifact you can show.
- An integration guide under 80 lines, matching Hook Design Lab's "public good other builders can reuse" language directly, with a working example instead of a promise.
- Zero regression risk to the 181 existing tests if the sequencing in Section 7 is followed — you're not rewriting logic, you're relocating it.
- An honest, stated scope boundary (single-asset-per-instance) instead of an overclaimed multi-token feature that doesn't actually work end-to-end yet.
