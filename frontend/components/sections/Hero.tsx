import Image from "next/image";
import { Badge } from "@/components/ui/Badge";

export function Hero() {
  return (
    <section id="main-content" className="relative flex flex-col items-center justify-center text-center min-h-screen pt-20 px-6 overflow-hidden">
      <div className="absolute inset-0 pointer-events-none"
        style={{
          backgroundImage: "linear-gradient(rgba(232,163,61,0.04) 1px, transparent 1px), linear-gradient(90deg, rgba(232,163,61,0.04) 1px, transparent 1px)",
          backgroundSize: "64px 64px",
        }}/>
      <div className="absolute inset-0 pointer-events-none"
        style={{
          background: "radial-gradient(ellipse 80% 60% at 50% 40%, rgba(232,163,61,0.08) 0%, transparent 70%)"
        }}/>

      <div className="relative z-10 max-w-4xl mx-auto">
        <Badge pulse className="mb-8">
          LIVE ON UNICHAIN SEPOLIA · REACTIVE NETWORK AUTOMATION
        </Badge>

        <h1 className="fade-up-delay-1 font-black tracking-tight mb-6 text-[clamp(2.8rem,7vw,5.5rem)] leading-[1.05] -tracking-[2px] font-display">
          Your Liquidity,<br/>
          <span className="text-signal">Always at Work.</span>
        </h1>

        <p className="fade-up-delay-2 max-w-2xl mx-auto mb-10 text-[clamp(1rem,2vw,1.25rem)] text-slate leading-[1.7]">
          A <strong className="text-paper">Reactive Yield Automation</strong> built as a Uniswap v4 hook.
          When your USDC exits its range, capital routes to Compound V3 within the same block —
          recalled just-in-time before the next swap executes. Zero off-chain infrastructure.
          Each position is an on-chain NFT.
        </p>

        <div className="fade-up-delay-3 flex flex-wrap gap-4 justify-center">
          <a href="#contracts"
            className="rounded-[var(--radius-control)] px-8 py-[14px] font-bold text-base text-ink"
            style={{ background: "linear-gradient(135deg, #E8A33D, #D4892A)", boxShadow: "0 8px 32px rgba(232,163,61,0.3)" }}>
            View Deployed Contracts →
          </a>
          <a href="https://github.com/Majormaxx/stablestream/blob/main/docs/INTEGRATION_GUIDE.md"
            target="_blank"
            rel="noopener noreferrer"
            className="rounded-[var(--radius-control)] px-8 py-[14px] font-semibold text-base text-signal"
            style={{ border: "1px solid rgba(232,163,61,0.3)", background: "rgba(232,163,61,0.06)" }}>
            Read the Integration Guide
          </a>
        </div>
      </div>

      <div className="fade-up-delay-4 relative mt-20">
        <div style={{ width: 160, height: 160, filter: "drop-shadow(0 0 48px rgba(232,163,61,0.4))" }}>
          <Image src="/logo.svg" alt="StableStream mark" width={160} height={160} className="stream-pulse"/>
        </div>
      </div>
    </section>
  );
}
