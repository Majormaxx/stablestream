# Hookathon Rules & Context Guide

> This file captures all competition context, judging criteria, sponsor details,
> and strategic intelligence for building three winning Uniswap v4 hooks.

---

## Competition Overview

- **Program**: Uniswap Hook Incubator (UHI) Hookathon
- **Prize Pool**: $25,000+ (split across multiple winners)
- **Sponsors**: Reactive Network, Unichain, Uniswap Foundation
- **Max Submissions**: Up to 3 hooks per participant/team
- **Team Size**: Solo or up to 4 developers

---

## Binary Qualifications (Pass/Fail)

All of the following MUST be true or the submission is disqualified:

| Requirement                      | Details                                                                     |
| -------------------------------- | --------------------------------------------------------------------------- |
| Public GitHub Repo               | Must be public (private requires pre-approval)                              |
| Demo Video                       | <=5 minutes, explains the hook clearly                                      |
| Valid Hook                       | Must be a valid Uniswap v4 hook or directly interface with hooks            |
| Working Code                     | Functional code written during the Hookathon period                         |
| README with Partner Integrations | Clearly list where partner tech is integrated (no theoretical integrations) |
| Originality                      | No copied code from workshops, curriculum, or other devs without credit     |
| Tests OR Frontend                | Must include unit tests OR a basic frontend for judges to interact with     |

---

## Scored Evaluation (Weighted 0-5 Scale)

| Criteria               | Weight | What Judges Look For                                          |
| ---------------------- | ------ | ------------------------------------------------------------- |
| **Original Idea**      | 30%    | Novelty of concept - is it new to Uniswap or DeFi?            |
| **Unique Execution**   | 25%    | Architecture, integrations, optimizations, UX distinctiveness |
| **Impact**             | 20%    | Value to users, Uniswap ecosystem, or DeFi broadly            |
| **Functionality**      | 15%    | Does it work as intended? Robustness and completeness         |
| **Presentation Pitch** | 10%    | Clarity, persuasiveness, quality of video demo                |

### Strategic Priority Order

1. Original Idea (30%) - This is the single biggest differentiator
2. Unique Execution (25%) - How you build matters almost as much as what you build
3. Impact (20%) - Must solve a real problem for real users
4. Functionality (15%) - Must work, but doesn't need to be production-grade
5. Presentation (10%) - Clear storytelling, problem/solution framing

---

## Sponsor Technology Stack

### Reactive Network (PARSIQ)

- **What**: Reactive Smart Contracts (RSCs) - autonomous on-chain agents that react to events
- **Key Use Cases**: Automated TWAMM, oracle-based limit orders, dynamic fee adjustments, cross-chain automation
- **Integration**: Unichain mainnet support (origin + destination chain)
- **Prize Angle**: Hooks that automate complex multi-step logic without off-chain keepers

### Unichain

- **What**: Uniswap Labs' L2 rollup built on OP Stack
- **Key Features**: ~95% lower gas vs Ethereum, 1-second blocks, native USDC
- **Prize Angle**: Hooks deployed on Unichain, leveraging its speed and low cost
- **Grant Programs**: Unichain Grant Programs for DeFi projects

### Uniswap Foundation

- **What**: Core protocol steward
- **Prize Angle**: Hooks that grow the Uniswap ecosystem, solve LP problems (IL, LVR), bring new users/capital

### Circle (Past Sponsor - May Return)

- **What**: USDC issuer, CCTP cross-chain transfers, Paymaster, Smart Wallets
- **Prize Angle**: USDC-centric hooks, cross-chain stablecoin liquidity, gasless UX

### Fhenix (Past Sponsor - May Return)

- **What**: Fully Homomorphic Encryption (FHE) on-chain
- **Prize Angle**: Privacy-preserving hooks (encrypted orders, private comparisons)

---

## Request for Hooks Categories (from Atrium Academy)

1. LP optimization & dynamic fees
2. Incentives, rewards, and yield strategies
3. Cross-chain, Unichain, and routing solutions
4. MEV mitigation, execution, and orderflow improvements
5. Security, compliance, and risk management
6. Specialized markets (prediction markets, RWA, stablecoins)
7. Automated position managers
8. UX enhancers
9. Social token hooks
10. TradFi adoption enablers

---

## Past Winning Projects (Pattern Analysis)

### What Wins (Patterns from 400+ devs, $130K+ prizes)

| Pattern                | Examples                                                           |
| ---------------------- | ------------------------------------------------------------------ |
| Cross-chain automation | AnyPrice (cross-chain oracle), Async Swap                          |
| LP protection / yield  | Rehypothecation Hook (restaking idle ETH), Cork (depeg protection) |
| New market primitives  | Prediction Market Hook, Unipump (bonding curves)                   |
| MEV solutions          | Super DCA (0% fees for DCA), BackGeoOracle                         |
| Gamification           | QuestHook (lotteries/quests), ETHeroes (NFT rewards)               |
| Institutional tools    | MiladyBank (lending on v4), Compliance hooks                       |

### What Does NOT Win

- Simple fee adjustment hooks (too common)
- Hooks that only wrap existing functionality without novelty
- Theoretical integrations with no working code
- Copied or lightly modified workshop code

---

## Demo Video Best Practices

1. Start with the PROBLEM you're solving (30 seconds)
2. Explain HOW your hook works (60-90 seconds)
3. Show working code/tests OR live frontend demo (90-120 seconds)
4. Compare to existing solutions if relevant (30 seconds)
5. Close with impact and future vision (30 seconds)
6. Total: Keep under 5 minutes

---

## Submission Checklist

- [ ] Public GitHub repo with clean README
- [ ] README explicitly lists all partner integrations with code locations
- [ ] Demo video under 5 minutes uploaded (Loom/YouTube)
- [ ] Unit tests OR working frontend
- [ ] All code is original (credited if using any external code)
- [ ] Selected correct partners in submission form
- [ ] Submitted via Final Hookathon Submission form
- [ ] Progress updates submitted (Week 1 and Week 2)

---

## Development Standards

- Solidity ^0.8.26 with Foundry for testing
- Follow Uniswap v4 hook interface (IHooks)
- Target deployment on Unichain (low gas, fast blocks)
- Gas optimization matters - use transient storage where applicable
- Clean, well-documented code with NatSpec comments
- No emojis in code
- Commits: concise, simple, past active tense
