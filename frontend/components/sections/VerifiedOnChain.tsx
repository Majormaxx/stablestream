"use client";

import { useInView } from "@/lib/useInView";
import { ShieldCheck, FileCheck, Award } from "lucide-react";

export function VerifiedOnChain() {
  const { ref, inView } = useInView();

  const items = [
    {
      icon: <ShieldCheck size={24} className="text-current" />,
      stat: "161",
      label: "TESTS PASSING",
      sub: "11 suites · Fuzz tested · Every edge case documented",
      href: "https://github.com/Majormaxx/stablestream/actions",
      cta: "View on GitHub Actions",
      color: "text-current",
    },
    {
      icon: <Award size={24} className="text-signal" />,
      stat: "UHI8",
      label: "UNICHAIN ALUMNI PRIZE",
      sub: "Originated at the Uniswap Hook Incubator — winner of the Unichain Alumni Prize",
      href: null,
      cta: null,
      color: "text-signal",
    },
    {
      icon: <FileCheck size={24} className="text-current" />,
      stat: "4",
      label: "CONTRACTS VERIFIED",
      sub: "StableStreamHook · YieldRouter · CompoundV3Adapter · RangeMonitorRSC",
      href: "https://sepolia.uniscan.xyz/address/0xDB23B8Ff772fC1e29EB35a4BECe17f6D1a9A86C0",
      cta: "View on Uniscan",
      color: "text-current",
    },
  ];

  return (
    <section className="py-20 px-6 border-t border-rail/60">
      <div className="max-w-5xl mx-auto">
        <div className="audience-rule">
          <span className="audience-label">For Developers · For Liquidity Providers</span>
        </div>
        <div ref={ref} className={`text-center mb-12 transition-all duration-700 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
          <h2 className="font-black text-[clamp(1.6rem,3vw,2.4rem)] -tracking-[1px] font-display">
            Deployed. Auditable. Live.
          </h2>
          <p className="text-slate mt-3 max-w-[520px] mx-auto leading-[1.7] text-[0.9rem]">
            Every claim on this page is backed by on-chain contracts, passing tests, and verifiable provenance.
          </p>
        </div>
        <div className="grid md:grid-cols-3 gap-5">
          {items.map((item, i) => (
            <div
              key={item.label}
              className={`card-static rounded-[var(--radius-panel)] p-6 text-center transition-all duration-700 delay-${i * 100} ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}
              style={{ border: "1px solid var(--color-rail, #1E2621)", background: "rgba(20,26,23,0.6)" }}
            >
              <div className="flex justify-center mb-3">{item.icon}</div>
              <div className="font-mono text-[2rem] font-bold -tracking-[1px] text-paper">
                {item.stat}
              </div>
              <div className={`text-[0.7rem] font-mono tracking-[1.5px] mt-1 ${item.color}`}>
                {item.label}
              </div>
              <div className="text-slate text-[0.78rem] mt-3 leading-[1.6]">
                {item.sub}
              </div>
              {item.href && (
                <a
                  href={item.href}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-block mt-4 text-[0.78rem] font-semibold text-signal no-underline hover:underline"
                >
                  {item.cta} ↗
                </a>
              )}
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
