"use client";

import { useInView } from "@/lib/useInView";

const rows = [
  { youdBuild: "Position tracking (open, close, query by owner)", moduleGives: "3 public functions, 1 struct, 8 events" },
  { youdBuild: "Range detection (tick math, beforeSwap / afterSwap)", moduleGives: "4 hook callbacks, in-range / out-of-range events" },
  { youdBuild: "Yield routing (deposit to external protocol, track, recall)", moduleGives: "routeToYield / recallFromYield, YieldAccounting" },
  { youdBuild: "Dynamic fee scaling (yield ratio → swap fee)", moduleGives: "getDynamicFee()" },
  { youdBuild: "Rate limiting (per-block caps, cooldown, JIT bypass)", moduleGives: "POSITION_COOLDOWN_BLOCKS, MAX_CALLBACKS_PER_BLOCK" },
  { youdBuild: "Automation (event → callback chain)", moduleGives: "RangeMonitorRSC — deploy once, subscribe automatically" },
  { youdBuild: "APY safety (anomaly detection, risk scoring)", moduleGives: "APYVerifier (TWAP), RiskEngine" },
  { youdBuild: "Multi-source routing (Compound, Aave, native staking)", moduleGives: "YieldRouter with IYieldSource adapters" },
  { youdBuild: "Gas optimization (EIP-1153 transient storage)", moduleGives: "TransientStorage library" },
  { youdBuild: "Tests against edge cases and security invariants", moduleGives: "161 tests across 11 suites" },
];

export function WhyNotBuildYourOwn() {
  const { ref, inView } = useInView();

  return (
    <section className="py-24 px-6 border-t border-rail/60 bg-channel/40">
      <div className="max-w-5xl mx-auto">
        <div className="audience-rule">
          <span className="audience-label">For Developers</span>
        </div>
        <div ref={ref} className={`text-center mb-12 transition-all duration-700 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
          <p className="text-signal font-mono text-[0.7rem] tracking-[2px] mb-3">IDLECAPITALYIELDMODULE</p>
          <h2 className="font-black text-[clamp(2rem,4vw,3rem)] -tracking-[1px] mb-4 font-display">
            Two Days vs. Two Months
          </h2>
          <p className="text-slate max-w-[560px] mx-auto leading-[1.7] text-[0.95rem]">
            What you would have to reimplement from scratch — and what{" "}
            <code className="text-signal font-mono text-[0.85rem]">IdleCapitalYieldModule</code> gives you for free.
          </p>
        </div>

        <div className={`overflow-x-auto transition-all duration-700 delay-100 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
          <table className="w-full text-left text-[0.85rem] border-collapse">
            <thead>
              <tr className="border-b border-rail">
                <th className="py-4 pr-6 font-mono text-[0.7rem] tracking-[1.5px] text-slate uppercase w-[45%]">You would build</th>
                <th className="py-4 font-mono text-[0.7rem] tracking-[1.5px] text-slate uppercase">IdleCapitalYieldModule gives you</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.youdBuild} className="border-b border-rail/40">
                  <td className="py-3 pr-6 text-slate align-top">{row.youdBuild}</td>
                  <td className="py-3 text-paper align-top font-medium">{row.moduleGives}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className={`text-center mt-10 transition-all duration-700 delay-200 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
          <a
            href="/docs/integration-guide"
            className="inline-block rounded-[var(--radius-control)] px-8 py-[14px] font-bold text-base text-ink no-underline"
            style={{ background: "linear-gradient(135deg, #E8A33D, #D4892A)", boxShadow: "0 8px 32px rgba(232,163,61,0.3)" }}
          >
            Read the Integration Guide →
          </a>
          <p className="mt-4 text-slate text-[0.8rem]">
            Or see the proof:{" "}
            <a
              href="https://github.com/Majormaxx/stablestream/blob/main/test/core/MinimalHook.t.sol"
              target="_blank" rel="noopener noreferrer"
              className="text-signal underline"
            >
              MinimalHook.t.sol
            </a>
          </p>
        </div>
      </div>
    </section>
  );
}
