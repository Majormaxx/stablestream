"use client";

import { useInView } from "@/lib/useInView";
import { CodeBlock } from "@/components/ui/CodeBlock";

const MY_HOOK_CODE = `contract MyHook is IdleCapitalYieldModule {
    constructor(IPoolManager pm, YieldRouter router, address asset, address owner)
        IdleCapitalYieldModule(pm, router, asset, owner)
    {}
}`;

const MINIMAL_HOOK_CODE = `contract MinimalHook is IdleCapitalYieldModule {
    constructor(
        IPoolManager _poolManager,
        YieldRouter _yieldRouter,
        address _usdc,
        address _owner
    ) IdleCapitalYieldModule(_poolManager, _yieldRouter, _usdc, _owner) {}
}`;

export function ModuleSection() {
  const { ref, inView } = useInView();

  return (
    <section id="module" className="py-28 px-6 border-t border-brand-500/10">
      <div className="max-w-5xl mx-auto">
        <div ref={ref} className={`text-center mb-16 transition-all duration-700 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
          <p className="text-brand-400 font-semibold text-[0.8rem] tracking-[2px] mb-3">THE PRIMITIVE UNDERNEATH</p>
          <h2 className="font-black text-[clamp(2rem,4vw,3rem)] -tracking-[1px] mb-4">
            StableStream is the reference implementation. This is the module.
          </h2>
          <p className="text-text-muted text-[0.95rem] leading-[1.7] max-w-[640px] mx-auto">
            <code className="text-brand-400 font-mono text-[0.9rem]">IdleCapitalYieldModule</code> is an abstract Solidity contract providing reusable idle-capital yield routing for any Uniswap v4 hook. Inherit it to get position tracking, four callback hooks, and RSC-triggered yield routing — zero product coupling.
          </p>
        </div>

        <div className="grid md:grid-cols-2 gap-8 max-w-4xl mx-auto">
          <div className={`transition-all duration-700 delay-100 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
            <CodeBlock
              code={MY_HOOK_CODE}
              language="solidity"
              caption="<strong className='text-green-400'>11 lines</strong> — your hook inherits all position tracking, yield routing, and RSC automation."
            />
          </div>
          <div className={`transition-all duration-700 delay-200 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
            <CodeBlock
              code={MINIMAL_HOOK_CODE}
              language="solidity"
              caption={
                <>
                  <span className="text-green-400 font-semibold">11 tests</span> in{" "}
                  <a href="https://github.com/Majormaxx/stablestream/blob/main/test/core/MinimalHook.t.sol"
                    target="_blank" rel="noopener noreferrer"
                    className="text-brand-400 underline">
                    MinimalHookTest
                  </a>{" "}
                  prove this module works with zero StableStream-specific code.
                </>
              }
            />
          </div>
        </div>

        <div className={`text-center mt-12 transition-all duration-700 delay-300 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
          <p className="text-text-muted text-[0.85rem] mb-6 leading-[1.7] max-w-[520px] mx-auto">
            <span className="stream-pulse inline-block w-[6px] h-[6px] rounded-full bg-cyan-400 align-middle mr-2"/>
            Reactive Network RSC fires callbacks within the same block — no bots, no cron jobs, no oracles.
          </p>
          <a
            href="https://github.com/Majormaxx/stablestream/blob/main/docs/INTEGRATION_GUIDE.md"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-block rounded-[12px] px-8 py-[14px] font-bold text-base text-white"
            style={{ background: "linear-gradient(135deg, #0066FF, #00AAFF)", boxShadow: "0 8px 32px rgba(0,102,255,0.35)" }}
          >
            Read the Integration Guide →
          </a>
        </div>
      </div>
    </section>
  );
}
