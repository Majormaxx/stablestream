"use client";

import { useInView } from "@/lib/useInView";

const steps = [
  { step: "01", color: "#0066FF", title: "Position Created", desc: "You add liquidity to Uniswap. We mint an NFT that tracks your position and ongoing yield." },
  { step: "02", color: "#00AAFF", title: "Price Exits Range", desc: "When the market moves and your position temporarily leaves the trading range, our system detects this instantly." },
  { step: "03", color: "#00D4FF", title: "Yield Activates", desc: "Your idle capital automatically shifts to the highest-paying yield source (Compound or Aave). Earning starts now." },
  { step: "04", color: "#FFB800", title: "Price Returns", desc: "When the market swings back, your capital returns automatically—ready to earn trading fees again." },
];

export function ArchitectureSteps() {
  const { ref, inView } = useInView();

  return (
    <section id="architecture" className="py-28 px-6 bg-bg-card/60 border-y border-brand-500/10">
      <div className="max-w-5xl mx-auto">
        <div className="text-center mb-16">
          <p className="text-brand-400 font-semibold text-[0.8rem] tracking-[2px]">SYSTEM ARCHITECTURE</p>
          <h2 className="font-black mt-3 text-[clamp(2rem,4vw,3rem)] -tracking-[1px]">
            How StableStream Works
          </h2>
        </div>
        <div ref={ref} className={`flex flex-col gap-4 transition-all duration-700 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
          {steps.map((step) => (
            <div key={step.step} className="flex items-start gap-6 rounded-2xl p-6 card-hover"
              style={{ border: "1px solid rgba(0,102,255,0.15)", background: "rgba(5,10,20,0.6)" }}>
              <div className="text-[1.8rem] font-black min-w-[56px] -tracking-[1px] opacity-90" style={{ color: step.color }}>{step.step}</div>
              <div>
                <div className="font-bold text-[1.05rem] mb-1">{step.title}</div>
                <div className="text-text-muted text-[0.875rem] leading-[1.7]">{step.desc}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
