# STABLESTREAM — AGENT IMPLEMENTATION GUIDE

> The single source of truth for implementing the complete StableStream submission.
> Every workstream in this document must be implemented to achieve 100% compliance.

---

## VERIFIED ADDRESSES (Unichain Sepolia — Chain ID 1301)

| Contract | Address | Source |
|---|---|---|
| USDC | `0x31d0220469e10c4E71834a79b1f276d740d3768F` | Circle official (verified on-chain) |
| WETH | `0x4200000000000000000000000000000000000006` | OP Stack predeploy |
| Aave V3 Pool | `0x32283a2169B0C462C69036c0aA17C3D063A482A1` | Aave official docs |
| Aave PoolAddressesProvider | `0x036e2FB9660AC2B9F96D23D3099B1c04A9D24F3b` | Aave official docs |
| Compound V3 USDC Comet | `0x2a02B9a5C58a67Cf695fD1D92d18D56fdFbBC40e` | Compound official |
| Uniswap v4 PoolManager | `0x1F98400000000000000000000000000000000004` | Uniswap official |

---

## 1. WORKSTREAM 1: PROJECT SCAFFOLDING

### File: `foundry.toml`

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.26"
evm_version = "cancun"
optimizer = true
optimizer_runs = 200
via_ir = true
```

### File: `.env.example`

```bash
# Unichain Sepolia RPC
UNICHAIN_SEPOLIA_RPC=https://sepolia.unichain.org

# Unichain Mainnet RPC
UNICHAIN_RPC=https://mainnet.unichain.org

# Deployer private key (NEVER commit this file with real values)
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Etherscan API key — Uniscan is powered by Etherscan API V2, one key covers Unichain + 60+ chains
ETHERSCAN_API_KEY=

# Reactive Network RPC (Kopli testnet)
REACTIVE_RPC=https://kopli-rpc.rnk.dev/
REACTIVE_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

---

## 2. WORKSTREAM 2: EIP-1153 TRANSIENT STORAGE

### File: `src/libraries/TransientStorage.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title TransientStorage
/// @notice Gas-efficient transient storage helpers using EIP-1153 TSTORE/TLOAD.
///         Saves ~19,900 gas per flag compared to cold SSTORE/SLOAD.
///         Requires evm_version = "cancun" in foundry.toml.
library TransientStorage {
    /// @notice Write a bool to transient storage at the given slot.
    function tstore(bytes32 slot, bool value) internal {
        assembly {
            tstore(slot, value)
        }
    }

    /// @notice Read a bool from transient storage.
    function tload(bytes32 slot) internal view returns (bool value) {
        assembly {
            value := tload(slot)
        }
    }

    /// @notice Compute a unique slot for a (prefix, key) pair.
    function slotFor(bytes32 prefix, bytes32 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(prefix, key));
    }
}
```

### Integration in `StableStreamHook.sol`

```solidity
// REMOVE:
mapping(bytes32 => bool) public pendingRecall;

// ADD (in state):
bytes32 private constant PENDING_RECALL_PREFIX = keccak256("StableStream.pendingRecall");

// REPLACE pendingRecall[posId] = true:
TransientStorage.tstore(TransientStorage.slotFor(PENDING_RECALL_PREFIX, posId), true);

// REPLACE pendingRecall[posId]:
TransientStorage.tload(TransientStorage.slotFor(PENDING_RECALL_PREFIX, posId))

// ADD view function:
function isPendingRecall(bytes32 positionId) external view returns (bool) {
    return TransientStorage.tload(TransientStorage.slotFor(PENDING_RECALL_PREFIX, positionId));
}
```

### Tests in `test/TransientStorage.t.sol`

```
test_tstore_tload_roundtrip()
test_tstore_clearsOnNewTransaction()
test_slotFor_differentKeys_differentSlots()
test_slotFor_differentPrefixes_differentSlots()
```

---

## 3. WORKSTREAM 3: DYNAMIC FEE MODULE

### File: `src/DynamicFeeModule.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title DynamicFeeModule
/// @notice Adjusts swap fees based on what fraction of pool liquidity is
///         currently deployed to external yield sources.
///
/// @dev    Fee logic:
///           yieldRatio = yieldCapital / totalPoolCapital
///           fee = BASE_FEE + (yieldRatio * MAX_YIELD_PREMIUM / 1e18)
///
///         At 0% yield utilisation   → BASE_FEE (300 bps = 0.30%)
///         At 100% yield utilisation → BASE_FEE + MAX_YIELD_PREMIUM (550 bps = 0.55%)
///
///         This rewards LPs who take on yield-routing execution risk and
///         compensates the pool for temporary liquidity depth reductions.
library DynamicFeeModule {
    uint24 public constant BASE_FEE = 3000;           // 0.30%
    uint24 public constant MAX_YIELD_PREMIUM = 2500;  // +0.25% when fully deployed
    uint24 public constant MAX_FEE = 10000;           // 1.00% hard cap

    /// @notice Compute the dynamic fee given current pool capital snapshot.
    /// @param totalCapital   Total USDC tracked in the pool (principal + yield).
    /// @param yieldCapital   USDC currently routed to external yield sources.
    /// @return fee           Fee in hundredths of a bip (Uniswap v4 native unit).
    function computeFee(uint256 totalCapital, uint256 yieldCapital)
        internal
        pure
        returns (uint24 fee)
    {
        if (totalCapital == 0 || yieldCapital == 0) return BASE_FEE;

        // yieldRatio in 1e18 fixed-point
        uint256 yieldRatio = (yieldCapital * 1e18) / totalCapital;
        if (yieldRatio > 1e18) yieldRatio = 1e18; // cap at 100%

        uint256 premium = (yieldRatio * MAX_YIELD_PREMIUM) / 1e18;
        uint256 computed = BASE_FEE + premium;
        fee = computed > MAX_FEE ? MAX_FEE : uint24(computed);
    }
}
```

### Integration in `StableStreamHook.sol`

```solidity
import {DynamicFeeModule} from "./DynamicFeeModule.sol";

// ADD to state:
mapping(PoolId => uint256) public poolTotalCapital;
mapping(PoolId => uint256) public poolYieldCapital;

// ADD internal helper:
function _poolCapitalSnapshot(PoolId pid, uint256 totalDelta, uint256 yieldDelta, bool isDeposit)
    internal
{
    if (isDeposit) {
        poolTotalCapital[pid] += totalDelta;
        poolYieldCapital[pid] += yieldDelta;
    } else {
        poolTotalCapital[pid] = poolTotalCapital[pid] > totalDelta ? poolTotalCapital[pid] - totalDelta : 0;
        poolYieldCapital[pid] = poolYieldCapital[pid] > yieldDelta ? poolYieldCapital[pid] - yieldDelta : 0;
    }
}

// MODIFY beforeSwap() to return dynamic fee:
// After existing logic, compute and return:
uint24 fee = DynamicFeeModule.computeFee(poolTotalCapital[id], poolYieldCapital[id]);
// Return fee as part of beforeSwap return value
```

### Tests in `test/DynamicFee.t.sol`

```
test_computeFee_returnsBaseFeeWhenNoYield()
test_computeFee_returnsMaxFeeWhenFullyDeployed()
test_computeFee_scalesLinearlyWithYieldRatio()
test_computeFee_neverExceedsMaxFee()
test_computeFee_handlesZeroTotalCapital()
```

---

## 4. WORKSTREAM 4: APY VERIFIER

### File: `src/libraries/APYVerifier.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title APYVerifier
/// @notice TWAP-based APY anomaly detection for yield source validation.
///         Prevents routing to compromised adapters reporting inflated APY.
library APYVerifier {
    /// @notice Rolling APY snapshot for a yield source.
    struct APYSnapshot {
        uint256[8] samples;  // circular buffer of last 8 APY readings
        uint8 head;          // current write index
        uint8 count;         // number of valid samples (max 8)
    }

    /// @notice Maximum deviation from TWAP before APY is flagged anomalous.
    ///         200 bps = 2.00% absolute deviation allowed.
    uint256 internal constant MAX_DEVIATION_BPS = 200;

    /// @notice Update the snapshot with a new APY reading.
    function update(APYSnapshot storage snap, uint256 newAPY) internal {
        snap.samples[snap.head] = newAPY;
        snap.head = (snap.head + 1) % 8;
        if (snap.count < 8) snap.count++;
    }

    /// @notice Compute the time-weighted average APY from the snapshot.
    function twap(APYSnapshot storage snap) internal view returns (uint256 avg) {
        if (snap.count == 0) return 0;
        uint256 sum;
        for (uint256 i = 0; i < snap.count; i++) sum += snap.samples[i];
        avg = sum / snap.count;
    }

    /// @notice Returns true if newAPY is within MAX_DEVIATION_BPS of the TWAP.
    ///         If fewer than 2 samples exist, always returns true (no history yet).
    function isWithinBounds(APYSnapshot storage snap, uint256 newAPY)
        internal
        view
        returns (bool)
    {
        if (snap.count < 2) return true;
        uint256 avg = twap(snap);
        if (avg == 0) return true;
        uint256 deviation = newAPY > avg ? newAPY - avg : avg - newAPY;
        return (deviation * 10_000) / avg <= MAX_DEVIATION_BPS;
    }
}
```

### Integration in `YieldRouter.sol`

```solidity
import {APYVerifier} from "./libraries/APYVerifier.sol";

// ADD to state:
mapping(address source => APYVerifier.APYSnapshot) public apySnapshots;

// ADD admin function:
function initializeAPYSnapshot(address source, uint256 seedAPY) external onlyOwner {
    _requireRegistered(source);
    apySnapshots[source].update(seedAPY);
    apySnapshots[source].update(seedAPY); // seed with 2 identical readings
}

// MODIFY _bestSource() — wrap APY check with TWAP verification:
uint256 apy;
try IYieldSource(src).currentAPY() returns (uint256 a) { apy = a; } catch { apy = 0; }
if (!apySnapshots[src].isWithinBounds(apy)) continue; // skip anomalous
apySnapshots[src].update(apy);
```

### Tests in `test/APYVerifier.t.sol`

```
test_update_storesReadings()
test_twap_returnsCorrectAverage()
test_isWithinBounds_returnsTrueForFreshSnapshot()
test_isWithinBounds_rejectsAnomalousSpike()
test_isWithinBounds_acceptsNormalVariation()
```

---

## 5. WORKSTREAM 5: RISK ENGINE

### File: `src/libraries/RiskEngine.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title RiskEngine
/// @notice Risk-weighted yield source scoring for institutional-grade capital allocation.
library RiskEngine {
    struct RiskProfile {
        uint16 riskScore;        // 0 (safest) to 100 (highest risk)
        uint8  tvlTier;          // 1 = >$1B, 2 = >$100M, 3 = >$10M, 4 = <$10M
        bool   isAudited;
        bool   hasInsurance;
        uint64 deploymentAge;    // seconds since first production deploy
    }

    /// @notice Computes risk-adjusted APY: rawAPY * (100 - riskScore) / 100
    function riskAdjustedAPY(
        uint256 rawAPY,
        RiskProfile memory profile
    ) internal pure returns (uint256) {
        uint256 safetyMultiplier = 100 - uint256(profile.riskScore);
        return (rawAPY * safetyMultiplier) / 100;
    }

    /// @notice Returns true if source meets LP's minimum risk tolerance
    function meetsThreshold(
        RiskProfile memory profile,
        uint8 lpTolerance
    ) internal pure returns (bool) {
        uint16 maxRisk = uint16(lpTolerance) * 20;
        return profile.riskScore <= maxRisk;
    }
}
```

### Integration in `YieldRouter.sol`

```solidity
import {RiskEngine} from "./libraries/RiskEngine.sol";

// ADD to state:
mapping(address source => RiskEngine.RiskProfile) public sourceRiskProfiles;

// ADD admin function:
function setRiskProfile(address source, RiskEngine.RiskProfile calldata profile) external onlyOwner {
    _requireRegistered(source);
    sourceRiskProfiles[source] = profile;
}

// MODIFY _bestSource() — add riskTolerance parameter and filter:
function _bestSource(uint256 minAmount, uint8 riskTolerance) internal view returns (address best) {
    uint256 bestScore;
    for (uint256 i = 0; i < MAX_SOURCES; i++) {
        address src = sources[i];
        if (src == address(0)) continue;
        if (IYieldSource(src).maxDeposit() < minAmount) continue;

        RiskEngine.RiskProfile memory profile = sourceRiskProfiles[src];
        if (!RiskEngine.meetsThreshold(profile, riskTolerance)) continue;

        uint256 apy;
        try IYieldSource(src).currentAPY() returns (uint256 a) { apy = a; } catch { apy = 0; }

        if (!apySnapshots[src].isWithinBounds(apy)) continue;
        apySnapshots[src].update(apy);

        uint256 adjusted = RiskEngine.riskAdjustedAPY(apy, profile);
        if (adjusted > bestScore) {
            bestScore = adjusted;
            best = src;
        }
    }
    if (best == address(0)) revert NoActiveSources();
}
```

---

## 6. WORKSTREAM 6: MULTI-TOKEN SUPPORT

### Changes to `StableStreamHook.sol`

```solidity
// ADD to state:
mapping(address token => bool) public whitelistedStables;
mapping(address token => address) public tokenRouters;

// ADD admin functions:
function whitelistStablecoin(address token, address router) external onlyOwner {
    whitelistedStables[token] = true;
    tokenRouters[token] = router;
}

// ADD to TrackedPosition struct:
address asset;   // which stablecoin this position manages
```

---

## 7. WORKSTREAM 7: NFT POSITION RECEIPTS (ERC-721)

### File: `src/StableStreamNFT.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title StableStreamNFT
/// @notice ERC-721 representing managed LP positions in StableStream.
///         Makes positions transferable and composable.
contract StableStreamNFT is ERC721 {
    address public immutable hook;

    error OnlyHook();

    modifier onlyHook() {
        if (msg.sender != hook) revert OnlyHook();
        _;
    }

    constructor(address _hook) ERC721("StableStream Position", "ssLP") {
        hook = _hook;
    }

    function mint(address to, bytes32 positionId) external onlyHook {
        _mint(to, uint256(positionId));
    }

    function burn(bytes32 positionId) external onlyHook {
        _burn(uint256(positionId));
    }

    function positionOwner(bytes32 positionId) external view returns (address) {
        return ownerOf(uint256(positionId));
    }
}
```

---

## 8. WORKSTREAM 8: REACTIVE SMART CONTRACT (RSC)

### File: `src/reactive/StableStreamRSC.sol`

See full implementation in the contract file.

---

## 9. WORKSTREAM 9: REMOVE ALL TODOS & PRODUCTION-QUALITY CODE

### Mandatory Fixes

1. Replace string revert in `beforeRemoveLiquidity` with `error CapitalInYield(bytes32 positionId)`
2. Fix or document `_handleDeposit` liquidity calculation with NatSpec
3. Scan every file for TODO/FIXME/HACK/TEMP and resolve all

---

## 10. WORKSTREAM 10: UNICHAIN SEPOLIA TESTNET DEPLOYMENT

### Deploy Command

```bash
forge script script/Deploy.s.sol:DeployStableStream \
    --rpc-url https://sepolia.unichain.org \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv
```

---

## 11. WORKSTREAM 11: TEST SUITE EXPANSION

### Target: 45+ tests, 0 failures

New test files:
- `test/DynamicFee.t.sol` — 5 tests
- `test/TransientStorage.t.sol` — 4 tests
- `test/APYVerifier.t.sol` — 5 tests
- `test/RiskEngine.t.sol` — 5 tests
- `test/NFTPositions.t.sol` — 5 tests
- `test/MultiToken.t.sol` — 4 tests

---

## 12. WORKSTREAM 12: FRONTEND

### Tech Stack

Next.js 14 + TypeScript + wagmi v2 + viem + Tailwind CSS

### Color Palette

- Background: `#0A0E17`
- Accent: `#00D4AA`
- USDC Blue: `#2775CA`

---

## 13. WORKSTREAM 13: README.md

Full README with architecture diagram, partner integrations table, deployed addresses, test instructions, gas optimization section, risk framework.

---

## 14. WORKSTREAM 14: DEMO VIDEO SCRIPT

4:45 video: Problem (0:30) → Solution (1:15) → Live Demo (1:30) → Technical Depth (1:00) → Impact (0:30)

---

## JUDGING RUBRIC

| Criteria | Weight |
|---|---|
| Original Idea | 30% |
| Unique Execution | 25% |
| Impact | 20% |
| Functionality | 15% |
| Presentation | 10% |

---

## SUBMISSION DETAILS

- GitHub: https://github.com/Majormaxx/stablestream
- Target: Uniswap Hook Incubator (UHI8)
- Partners: Reactive Network, Unichain
- Tags: Dynamic Stablecoin Manager, Yield Routing, JIT Liquidity, LP Optimization, Reactive Smart Contracts, Risk-Weighted Routing, EIP-1153
