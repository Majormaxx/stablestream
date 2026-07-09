"use client";

import { useInView } from "@/lib/useInView";

const features = [
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
        <path d="M4 14 C8 8, 14 8, 14 14 C14 20, 20 20, 24 14" stroke="#00AAFF" strokeWidth="2.5" strokeLinecap="round" fill="none"/>
        <circle cx="4" cy="14" r="2.5" fill="#0066FF"/>
        <circle cx="24" cy="14" r="2.5" fill="#00D4FF"/>
        <circle cx="14" cy="14" r="3" fill="#FFB800"/>
      </svg>
    ),
    title: "Yield Routing",
    desc: "Idle capital automatically flows to the highest-paying yield source. Earn Compound's 2.8% or Aave's 3.2% on USDC—no decisions to make, no buttons to click.",
  },
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
        <polygon points="14,2 26,8 26,20 14,26 2,20 2,8" stroke="#00D4FF" strokeWidth="2" fill="none"/>
        <path d="M8 14 L12 18 L20 10" stroke="#FFB800" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
    ),
    title: "Seamless Integration",
    desc: "Built natively into Uniswap v4. Subscribe to your position, earn passively. Works with all your favorite Uniswap tools and wallets.",
  },
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
        <circle cx="14" cy="14" r="11" stroke="#0066FF" strokeWidth="2"/>
        <path d="M14 8 L14 14 L18 17" stroke="#00AAFF" strokeWidth="2.5" strokeLinecap="round"/>
        <circle cx="14" cy="14" r="2" fill="#FFB800"/>
      </svg>
    ),
    title: "Reactive Automation",
    desc: "RangeMonitorRSC on Reactive Network Lasna subscribes to hook events and fires callbacks within the same block — no bots, no cron jobs, no middlemen. JIT recall returns capital before the next swap executes.",
  },
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
        <rect x="3" y="3" width="10" height="10" rx="2" stroke="#00AAFF" strokeWidth="2"/>
        <rect x="15" y="3" width="10" height="10" rx="2" stroke="#00D4FF" strokeWidth="2"/>
        <rect x="3" y="15" width="10" height="10" rx="2" stroke="#0066FF" strokeWidth="2"/>
        <rect x="15" y="15" width="10" height="10" rx="2" stroke="#FFB800" strokeWidth="2"/>
        <circle cx="14" cy="14" r="2.5" fill="#FFFFFF"/>
      </svg>
    ),
    title: "NFT Positions",
    desc: "Each liquidity position is represented as an on-chain NFT. Composable, transferable, and queryable. Position state, yield accrued, and routing history all on-chain.",
  },
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
        <path d="M6 22 L6 12 L14 6 L22 12 L22 22 Z" stroke="#00D4FF" strokeWidth="2" fill="none"/>
        <path d="M10 22 L10 16 L14 13 L18 16 L18 22" stroke="#FFB800" strokeWidth="1.8" fill="none"/>
      </svg>
    ),
    title: "On-Chain APY Verification",
    desc: "APYVerifier rejects any yield source reporting more than 2x its trailing TWAP before capital ever moves — a compromised or manipulated adapter can't drain the pool. Contracts are unaudited; verify the logic yourself in libraries/APYVerifier.sol.",
  },
  {
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
        <circle cx="14" cy="14" r="11" stroke="#0066FF" strokeWidth="2"/>
        <path d="M9 14 C9 11, 11 9, 14 9 C17 9, 19 11, 19 14" stroke="#00AAFF" strokeWidth="2" fill="none"/>
        <path d="M9 14 C9 17, 11 19, 14 19" stroke="#FFB800" strokeWidth="2" strokeLinecap="round" fill="none"/>
        <circle cx="14" cy="19" r="2" fill="#FFB800"/>
      </svg>
    ),
    title: "Dynamic Fees",
    desc: "Swap fees scale with yield utilisation — when more capital is earning yield, the fee rises to compensate LPs for reduced pool depth. All computed on-chain by DynamicFeeModule.",
  },
];

export function Features() {
  const { ref, inView } = useInView();

  return (
    <section id="features" className="py-28 px-6">
      <div className="max-w-6xl mx-auto">
        <div className="text-center mb-16">
          <p className="text-brand-400 font-semibold text-[0.8rem] tracking-[2px]">PROTOCOL FEATURES</p>
          <h2 className="font-black mt-3 text-[clamp(2rem,4vw,3rem)] -tracking-[1px]">
            Built for Capital Efficiency
          </h2>
          <p className="text-text-muted mt-3 max-w-[480px] mx-auto leading-[1.7]">
            Every component of StableStream is designed to eliminate idle capital and maximise yield. Autonomously, trustlessly, on-chain.
          </p>
        </div>
        <div ref={ref} className={`grid md:grid-cols-2 lg:grid-cols-3 gap-6 transition-all duration-700 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
          {features.map((f) => (
            <div key={f.title} className="card-hover rounded-2xl p-6 border-glow">
              <div className="mb-4">{f.icon}</div>
              <h3 className="font-bold text-[1.05rem] mb-2">{f.title}</h3>
              <p className="text-text-muted text-[0.875rem] leading-[1.7]">{f.desc}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
