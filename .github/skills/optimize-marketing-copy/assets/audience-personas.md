# Audience Personas & Messaging Strategy

Use these personas to adapt copy tone, emphasis, and language for each segment.

---

## Persona 1: Retail LP (Passive Income Seeker)

### Demographics & Motivation
- **Profile:** Individual investor, mostly passive (check positions weekly/monthly)
- **Tech comfort:** Comfortable with MetaMask and basic DeFi, but not a developer
- **Goal:** Maximize yield on existing positions with minimal effort
- **Pain point:** Capital locked in out-of-range positions earning zero; manual rebalancing is tedious
- **Worry:** "Will I lose my funds? Is this too complicated?"

### Messaging Strategy
**Tone:** Friendly, reassuring, action-oriented  
**Focus:** Simplicity + passive income + safety  
**Avoid:** Complex mechanics, risk discussions, technical jargon  

### Key Copy Angles
✓ "Set and forget" — emphasize zero buttons to click  
✓ "Real yield" — cite actual APY (Compound 2.8%, Aave 3.2%)  
✓ "Your position stays safe" — reassure funds remain in their Uniswap NFT  
✓ "In minutes" — lower perceived friction  
✓ "Earn while you wait" — passive benefit focus  

### Example Copy
```
"Your out-of-range positions don't have to earn zero. 
Connect your wallet, deposit USDC, and StableStream automatically 
earns you Compound's 2.8% while you wait for the price to move back 
into range. No buttons. No fees unless you earn."
```

### Visual/UX Cues
- Emphasize the green "APY gains" metric on dashboard
- Use simple, step-by-step onboarding flow ("Connect → Deposit → Earn")
- Avoid showing complex Risk Engine deep-dives or architecture diagrams

---

## Persona 2: Institutional/Sophisticated LP (Capital Efficiency)

### Demographics & Motivation
- **Profile:** Fund manager, institutional treasury, or sophisticated individual managing significant capital
- **Tech comfort:** Deep DeFi expertise; understands smart contracts, risk management, composability
- **Goal:** Maximize capital efficiency; reduce idle capital drag; trustless execution
- **Pain point:** Manual rebalancing overhead; counterparty risk from centralized intermediaries; complexity tradeoff
- **Worry:** "How does this validate APY? What are the failure modes? Is the architecture battle-tested?"

### Messaging Strategy
**Tone:** Professional, precise, technical  
**Focus:** Capital efficiency + institutional risk controls + trustlessness  
**Avoid:** Oversimplification, hype, unqualified claims  

### Key Copy Angles
✓ "Trustless, decentralized execution" — mention Reactive RSC specifically  
✓ "Risk Engine validation" — emphasize on-chain protection against manipulation  
✓ "No keeper bots" — appeal to decentralization values  
✓ "Institutional-grade capital efficiency" — credibility positioning  
✓ "Composable on-chain" — technical composability for custom models  
✓ "Transparent, auditable" — full on-chain history and decision logs  

### Example Copy
```
"Autonomous capital efficiency with institutional-grade controls.

StableStream routes idle liquidity to verified yield sources (Aave, Compound) 
using trustless on-chain validation. Our Risk Engine prevents 
manipulation; Reactive Network ensures decentralized event monitoring. 
Every routing decision is on-chain, auditable, and transparent. 

No centralized intermediaries. No keeper bot risk. Full capital composability."
```

### Visual/UX Cues
- Include Risk Engine explanation and audit reports
- Show real-time APY validation data and decision logs
- Reference Reactive Network architecture
- Highlight composability: "Works with [partner protocols]"

---

## Persona 3: Developer/Protocol Partner (Technical Integration)

### Demographics & Motivation
- **Profile:** Protocol engineer, integration builder, yield protocol founder
- **Tech comfort:** Expert-level; reads contracts, understands hook architecture, Uniswap v4 internals
- **Goal:** Integrate yield routing natively; extend to new protocols; reduce dev overhead
- **Pain point:** Custom oracle integrations, keeper infrastructure, limited composability with existing protocols
- **Worry:** "Are the hooks audited? Can I customize fee logic? What's the integration path?"

### Messaging Strategy
**Tone:** Technical, architecture-focused, reference-style  
**Focus:** Composability + extensibility + battle-tested patterns  
**Avoid:** Marketing fluff, excessive simplification, glossing over technical details  

### Key Copy Angles
✓ "Native Uniswap v4 hook integration" — emphasize architectural fit  
✓ "Custom adapters for new protocols" — extensibility  
✓ "Deterministic, on-chain validation" — avoid external dependencies  
✓ "Composable position NFTs" — programmatic access for custom UIs  
✓ "Audited, battle-tested patterns" — credibility from proven deployments  
✓ "Fine-grained event monitoring" — Reactive Network advantages  

### Example Copy
```
"Build yield strategies natively on Uniswap v4.

StableStream's hook architecture integrates directly into the 
Uniswap v4 swap lifecycle (beforeSwap, afterSwap). Extend routing 
to new protocols via pluggable adapters. Monitor positions in 
real-time without keeper bots—Reactive Network provides 
deterministic event validation.

On-chain composable NFT positions enable custom frontends and 
risk models. Audited, battle-tested patterns from production deployments."
```

### Visual/UX Cues
- Link to contract code, audit reports, deployment history
- Show hook lifecycle diagrams and adapter architecture
- Highlight past integration case studies
- Provide integration checklist and example code snippets

---

## Messaging Variations: Same Feature, Different Audiences

### Feature: Reactive Automation

**For Retail:**
```
"Your position is monitored 24/7 by Reactive Network—an independent 
decentralized system. So when you go out of range, StableStream knows 
instantly and routes your idle USDC to earn yield. No middleman. 
No delays. Just automatic."
```

**For Institutions:**
```
"Reactive Network provides decentralized, deterministic event monitoring 
without centralized keeper bot infrastructure. Sub-second latency. 
No counterparty risk. Full on-chain auditability."
```

**For Developers:**
```
"Event-driven architecture via Reactive RSC. Fine-grained conditionals 
on state changes without querying external oracles or running custom 
keeper infrastructure. Enables scalable, auditable automation."
```

---

## Tone Markers

| Aspect | Retail | Institutional | Developer |
|--------|--------|---------------|-----------|
| **Sentence Length** | Short, conversational (6–10 words avg) | Medium, precise (8–14 words avg) | Long, technical (12–20 words avg) |
| **Jargon** | Minimal; explain any terms | Moderate; assume DeFi fluency | High; contract-level detail |
| **Metaphor/Analogy** | Everyday ("works while you sleep") | Market-based ("capital efficiency") | Technical ("state machine") |
| **Numbers/Data** | Specific APY (2.8%) | Efficiency gains %, risk metrics | Gas costs, latency, throughput |
| **Proof** | Simple testimonial/"Set & forget" | Audits, risk controls, composability | Contracts, test coverage, deployments |
| **CTA Urgency** | Moderate ("Start Earning Today") | Low-key ("Explore Docs") | Matter-of-fact ("Integrate Now") |

---

## Copywriting Tips Per Audience

### For Retail Users:
1. **Remove friction words**: Replace "execute", "route", "rebalance" with "earn", "automatic", "just work"
2. **Lead with benefit**: "Earn 2.8%..." not "StableStream deploys capital to Compound V3..."
3. **Use second person**: "Your positions", "Your yield" (not "positions", "yield")
4. **Reassure**: Mention safety, transparency, no middlemen

### For Institutional Users:
1. **Lead with mechanism**: "Trustless validation via Risk Engine..." before outcome
2. **Cite sources**: Real APY from Aave/Compound; Reactive Network as independent system
3. **Use third person**: Professional tone; less "you", more "users", "LPs", "capital"
4. **Build credibility**: Audits, deployments, risk framework details

### For Developers:
1. **Use technical terms precisely**: "beforeSwap hook", "deterministic oracle", "adapter interface"
2. **Show, don't tell**: Link to code, show architecture diagrams, reference test suites
3. **Assume expertise**: Don't waste time explaining Uniswap v4 basics; jump to integration
4. **Focus on extensibility**: What can developers build on top?

---

*Tailor copy using these personas to ensure messaging resonates with each audience segment and drives engagement.*
