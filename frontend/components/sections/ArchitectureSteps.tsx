"use client";

import { useInView } from "@/lib/useInView";

const steps = [
  { step: "01", title: "Position Created", desc: "You deposit USDC as concentrated liquidity. The module mints an on-chain position receipt and begins tracking your tick range." },
  { step: "02", title: "Price Exits Range", desc: "When the market moves and your tick leaves the active range, the module emits an event. Reactive Network sees it within the same block." },
  { step: "03", title: "Yield Activates", desc: "The RSC calls routeToYield. Your idle capital shifts to Compound V3 — automatically, no buttons, no bots." },
  { step: "04", title: "Price Returns — JIT Recall", desc: "The next swap approaching your range triggers beforeSwap. The RSC calls recallFromYield within the same block. Capital is back before the swap executes." },
];

export function ArchitectureSteps() {
  const { ref, inView } = useInView();

  return (
    <section id="architecture" className="py-28 px-6 bg-channel/40 border-y border-rail/60">
      <div className="max-w-4xl mx-auto">
        <div className="text-center mb-16">
          <p className="text-signal font-mono text-[0.7rem] tracking-[2px] mb-3">SYSTEM ARCHITECTURE</p>
          <h2 className="font-black mt-3 text-[clamp(2rem,4vw,3rem)] -tracking-[1px] font-display">
            How StableStream Works
          </h2>
        </div>
        <div ref={ref} className={`process-line transition-all duration-700 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
          {steps.map((step) => (
            <div key={step.step} className="flex items-start gap-6 rounded-[var(--radius-panel)] p-6 card-static"
              style={{ border: "1px solid var(--color-rail, #1E2621)", background: "rgba(20,26,23,0.5)" }}>
              <div className="font-mono text-[1.8rem] font-bold min-w-[56px] -tracking-[1px] text-signal opacity-80">{step.step}</div>
              <div>
                <div className="font-bold text-[1.05rem] text-paper mb-1">{step.title}</div>
                <div className="text-slate text-[0.875rem] leading-[1.7]">{step.desc}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
