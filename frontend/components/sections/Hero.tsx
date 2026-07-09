import Image from "next/image";
import { Badge } from "@/components/ui/Badge";

export function Hero() {
  return (
    <section id="main-content" className="relative flex flex-col items-center justify-center text-center min-h-screen pt-20 px-6 overflow-hidden">
      <div className="absolute inset-0 pointer-events-none"
        style={{
          backgroundImage: "linear-gradient(rgba(0,102,255,0.05) 1px, transparent 1px), linear-gradient(90deg, rgba(0,102,255,0.05) 1px, transparent 1px)",
          backgroundSize: "64px 64px",
        }}/>
      <div className="absolute inset-0 pointer-events-none"
        style={{
          background: "radial-gradient(ellipse 80% 60% at 50% 40%, rgba(0,102,255,0.12) 0%, transparent 70%)"
        }}/>

      <div className="relative z-10 max-w-4xl mx-auto">
        <Badge pulse className="mb-8">
          DYNAMIC STABLECOIN MANAGER · UNISWAP v4 HOOKATHON · REACTIVE NETWORK
        </Badge>

        <h1 className="fade-up-delay-1 font-black tracking-tight mb-6 text-[clamp(2.8rem,7vw,5.5rem)] leading-[1.05] -tracking-[2px]">
          Your Liquidity,<br/>
          <span className="gradient-text">Always at Work.</span>
        </h1>

        <p className="fade-up-delay-2 max-w-2xl mx-auto mb-10 text-[clamp(1rem,2vw,1.25rem)] text-text-muted leading-[1.7]">
          A <strong className="text-brand-400">Dynamic Stablecoin Manager</strong> built as a Uniswap v4 hook.
          Out-of-range USDC earns yield via Compound V3 — recalled just-in-time by a{" "}
          <strong className="text-green-400">Reactive Network RSC</strong> with zero off-chain infrastructure.
          Each position is an <strong className="text-gold-400">on-chain NFT</strong>.
        </p>

        <div className="fade-up-delay-3 flex flex-wrap gap-4 justify-center">
          <a href="#contracts"
            className="rounded-[12px] px-8 py-[14px] font-bold text-base text-white"
            style={{ background: "linear-gradient(135deg, #0066FF, #00AAFF)", boxShadow: "0 8px 32px rgba(0,102,255,0.35)" }}>
            View Deployed Contracts →
          </a>
          <a href="#features"
            className="rounded-[12px] px-8 py-[14px] font-semibold text-base text-brand-400"
            style={{ border: "1px solid rgba(0,170,255,0.3)", background: "rgba(0,102,255,0.06)" }}>
            How It Works
          </a>
        </div>
      </div>

      <div className="fade-up-delay-4 relative mt-20">
        <div style={{ width: 160, height: 160, filter: "drop-shadow(0 0 48px rgba(0,102,255,0.5))" }}>
          <Image src="/logo.svg" alt="StableStream mark" width={160} height={160} className="stream-pulse"/>
        </div>
      </div>
    </section>
  );
}
