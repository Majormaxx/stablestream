"use client";

import { useInView } from "@/lib/useInView";

const features = [
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
        <path d="M4 14 C8 8, 14 8, 14 14 C14 20, 20 20, 24 14" stroke="#E8A33D" strokeWidth="2.5" strokeLinecap="round" fill="none"/>
        <circle cx="4" cy="14" r="2.5" fill="#E8A33D"/>
        <circle cx="24" cy="14" r="2.5" fill="#E8A33D"/>
        <circle cx="14" cy="14" r="3" fill="#3EC9B0"/>
      </svg>
    ),
    title: "Reactive Yield Routing",
    desc: "Idle capital automatically flows to Compound V3 the moment your position exits range. No decisions, no clicks, no keeper bots — the Reactive Network fires within the same block.",
  },
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
        <polygon points="14,2 26,8 26,20 14,26 2,20 2,8" stroke="#3EC9B0" strokeWidth="2" fill="none"/>
        <path d="M8 14 L12 18 L20 10" stroke="#E8A33D" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
    ),
    title: "Seamless Integration",
    desc: "Built natively into Uniswap v4. Deposit USDC, earn yield. Works with every wallet and every Uniswap tool — no new UI to learn, no additional contracts to manage.",
  },
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
        <circle cx="14" cy="14" r="11" stroke="#E8A33D" strokeWidth="2"/>
        <path d="M14 8 L14 14 L18 17" stroke="#3EC9B0" strokeWidth="2.5" strokeLinecap="round"/>
        <circle cx="14" cy="14" r="2" fill="#E8A33D"/>
      </svg>
    ),
    title: "Same-Block Automation",
    desc: "RangeMonitorRSC on Reactive Network subscribes to your hook's events and fires callbacks in the same block — JIT recall returns capital before the next swap executes. No off-chain infrastructure.",
  },
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
        <rect x="3" y="3" width="10" height="10" rx="2" stroke="#3EC9B0" strokeWidth="2"/>
        <rect x="15" y="3" width="10" height="10" rx="2" stroke="#3EC9B0" strokeWidth="2"/>
        <rect x="3" y="15" width="10" height="10" rx="2" stroke="#E8A33D" strokeWidth="2"/>
        <rect x="15" y="15" width="10" height="10" rx="2" stroke="#E8A33D" strokeWidth="2"/>
      </svg>
    ),
    title: "On-Chain Position NFTs",
    desc: "Every liquidity position is a transferable ERC-721. Position state, yield accrued, and routing history — all on-chain, all queryable.",
  },
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
        <path d="M6 22 L6 12 L14 6 L22 12 L22 22 Z" stroke="#3EC9B0" strokeWidth="2" fill="none"/>
        <path d="M10 22 L10 16 L14 13 L18 16 L18 22" stroke="#E8A33D" strokeWidth="1.8" fill="none"/>
      </svg>
    ),
    title: "On-Chain APY Verification",
    desc: "APYVerifier rejects any source reporting more than 2x its trailing TWAP before capital moves — a compromised adapter cannot drain the pool. Contracts are unaudited; verify the logic in libraries/APYVerifier.sol.",
  },
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
        <circle cx="14" cy="14" r="11" stroke="#E8A33D" strokeWidth="2"/>
        <path d="M9 14 C9 11, 11 9, 14 9 C17 9, 19 11, 19 14" stroke="#3EC9B0" strokeWidth="2" fill="none"/>
        <path d="M9 14 C9 17, 11 19, 14 19" stroke="#E8A33D" strokeWidth="2" strokeLinecap="round" fill="none"/>
        <circle cx="14" cy="19" r="2" fill="#E8A33D"/>
      </svg>
    ),
    title: "Dynamic Swap Fees",
    desc: "Swap fees scale with yield utilisation — when more capital is earning yield, the fee rises to compensate LPs for reduced pool depth. Computed on-chain by DynamicFeeModule.",
  },
];

export function Features() {
  const { ref, inView } = useInView();

  return (
    <section id="features" className="py-28 px-6">
      <div className="max-w-6xl mx-auto">
        <div className="text-center mb-16">
          <p className="text-signal font-mono text-[0.7rem] tracking-[2px]">PROTOCOL FEATURES</p>
          <h2 className="font-black mt-3 text-[clamp(2rem,4vw,3rem)] -tracking-[1px] font-display">
            Built for Capital Efficiency
          </h2>
          <p className="text-slate mt-3 max-w-[480px] mx-auto leading-[1.7]">
            Every component eliminates idle capital and maximises yield. Autonomously, trustlessly, on-chain.
          </p>
        </div>
        <div ref={ref} className={`grid md:grid-cols-2 lg:grid-cols-3 gap-6 transition-all duration-700 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
          {features.map((f) => (
            <div key={f.title} className="card-static rounded-[var(--radius-panel)] p-6"
              style={{ border: "1px solid var(--color-rail, #1E2621)", background: "rgba(20,26,23,0.5)" }}>
              <div className="mb-4">{f.icon}</div>
              <h3 className="font-bold text-[1.05rem] text-paper mb-2">{f.title}</h3>
              <p className="text-slate text-[0.875rem] leading-[1.7]">{f.desc}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
