"use client";

import { useInView } from "@/lib/useInView";
import { CodeBlock } from "@/components/ui/CodeBlock";
import { CheckCircle } from "lucide-react";

const MY_HOOK_CODE = `contract MyHook is IdleCapitalYieldModule {
    constructor(IPoolManager pm, YieldRouter router, address asset, address owner)
        IdleCapitalYieldModule(pm, router, asset, owner)
    {}
}`;

export function ModuleSection() {
  const { ref, inView } = useInView();

  return (
    <section id="module" className="py-28 px-6 border-t border-rail/60">
      <div className="max-w-5xl mx-auto">
        <div className="audience-rule">
          <span className="audience-label">For Developers</span>
        </div>
        <div ref={ref} className={`text-center mb-16 transition-all duration-700 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
          <p className="text-signal font-mono text-[0.7rem] tracking-[2px] mb-3">THE PRIMITIVE UNDERNEATH</p>
          <h2 className="font-black text-[clamp(2rem,4vw,3rem)] -tracking-[1px] mb-4 font-display">
            StableStream is the reference implementation. This is the module.
          </h2>
          <p className="text-slate text-[0.95rem] leading-[1.7] max-w-[640px] mx-auto">
            <code className="text-signal font-mono text-[0.85rem]">IdleCapitalYieldModule</code> is an abstract Solidity contract providing reusable idle-capital yield routing for any Uniswap v4 hook. Inherit it to get position tracking, four callback hooks, and RSC-triggered yield routing — zero product coupling.
          </p>
        </div>

        <div className="grid md:grid-cols-2 gap-8 max-w-4xl mx-auto">
          {/* Pitch panel — code + line count in header */}
          <div className={`transition-all duration-700 delay-100 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
            <CodeBlock
              code={MY_HOOK_CODE}
              language="solidity"
              label={
                <span className="flex items-center gap-3">
                  <span className="text-slate font-mono text-[0.65rem] tracking-[1.5px]">SOLIDITY</span>
                  <span className="text-signal font-mono text-[0.65rem] tracking-[1.5px]">· 11 LINES</span>
                </span>
              }
              caption="Your hook inherits all position tracking, yield routing, and RSC automation."
            />
          </div>

          {/* Proof card — stat-led, code secondary */}
          <div className={`transition-all duration-700 delay-200 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
            <div
              className="rounded-[var(--radius-panel)] p-6 h-full flex flex-col"
              style={{ border: "1px solid var(--color-rail, #1E2621)", background: "rgba(20,26,23,0.6)" }}
            >
              <div className="flex items-center gap-2 mb-4">
                <span className="text-slate font-mono text-[0.65rem] tracking-[1.5px]">PROOF</span>
              </div>

              <div className="flex items-center gap-3 mb-2">
                <span className="font-mono text-[2.8rem] font-bold -tracking-[1px] text-paper">11/11</span>
                <CheckCircle size={24} className="text-current" />
              </div>
              <div className="font-mono text-[0.7rem] tracking-[1px] text-current mb-4">
                MINIMALHOOK TESTS PASSING
              </div>
              <p className="text-slate text-[0.85rem] leading-[1.7] mb-6 flex-1">
                Proves the module works with zero StableStream-specific code. Inherit, deploy, route. 11 tests verify position tracking, access control, and yield routing — all independent of the reference implementation.
              </p>

              <div className="mt-auto">
                <details className="group">
                  <summary className="text-signal text-[0.78rem] font-semibold cursor-pointer list-none hover:opacity-80 transition-opacity">
                    <span className="group-open:hidden">View MinimalHook.sol ▾</span>
                    <span className="hidden group-open:inline">Hide code ▴</span>
                  </summary>
                  <pre className="mt-3 text-[0.78rem] leading-[1.6] font-mono text-slate bg-ink/60 rounded-[var(--radius-control)] p-4 overflow-x-auto">
                    <code>{`contract MinimalHook is IdleCapitalYieldModule {
    constructor(
        IPoolManager _poolManager,
        YieldRouter _yieldRouter,
        address _usdc,
        address _owner
    ) IdleCapitalYieldModule(_poolManager, _yieldRouter, _usdc, _owner) {}
}`}</code>
                  </pre>
                </details>
              </div>

              <a
                href="https://github.com/Majormaxx/stablestream/blob/main/test/core/MinimalHook.t.sol"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-block mt-4 text-[0.78rem] font-semibold text-slate no-underline hover:text-paper transition-colors"
              >
                View test suite on GitHub ↗
              </a>
            </div>
          </div>
        </div>

        <div className={`text-center mt-12 transition-all duration-700 delay-300 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
          <p className="text-slate text-[0.85rem] mb-6 leading-[1.7] max-w-[520px] mx-auto">
            <span className="stream-pulse inline-block w-[6px] h-[6px] rounded-full bg-current align-middle mr-2" />
            Reactive Network RSC fires callbacks within the same block — no bots, no cron jobs, no oracles.
          </p>
          <a
            href="/docs/integration-guide"
            className="inline-block rounded-[var(--radius-control)] px-8 py-[14px] font-bold text-base text-ink no-underline"
            style={{ background: "linear-gradient(135deg, #E8A33D, #D4892A)", boxShadow: "0 8px 32px rgba(232,163,61,0.3)" }}
          >
            Read the Integration Guide →
          </a>
        </div>
      </div>
    </section>
  );
}
