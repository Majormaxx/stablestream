"use client";

import Image from "next/image";
import { Suspense, useState } from "react";
import { useAccount } from "wagmi";
import { WalletButton } from "@/components/WalletButton";
import { ProtocolStats } from "@/components/ProtocolStats";
import { HookStatus } from "@/components/HookStatus";
import { ContractExplorer } from "@/components/ContractExplorer";
import { DepositForm } from "@/components/DepositForm";
import { MyPositions } from "@/components/MyPositions";
import { LiveHeroStats } from "@/components/LiveHeroStats";

function SectionSkeleton({ height = 280 }: { height?: number }) {
  return (
    <div
      aria-busy="true"
      aria-label="Loading section"
      style={{
        height,
        borderRadius: 16,
        margin: "0 24px",
        background: "linear-gradient(90deg, rgba(0,102,255,0.06) 25%, rgba(0,170,255,0.1) 50%, rgba(0,102,255,0.06) 75%)",
        backgroundSize: "200% 100%",
        animation: "shimmer 1.5s infinite",
      }}
    />
  );
}


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
    title: "Verified Safety",
    desc: "Every yield opportunity is verified on-chain before capital moves. We check the numbers to ensure you only earn real, sustainable yields. No surprises, no hidden risks.",
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


/* ── App section: gated behind wallet connection ───────── */
function AppSection() {
  const { isConnected } = useAccount();
  const [refreshKey, setRefreshKey] = useState(0);

  return (
    <section id="app" className="py-28 px-6"
      style={{ borderTop: "1px solid rgba(0,102,255,0.1)" }}>
      <div className="max-w-5xl mx-auto">
        <div className="text-center mb-12">
          <p style={{ color: "#00AAFF", fontWeight: 600, fontSize: "0.8rem", letterSpacing: "2px" }}>PROTOCOL INTERFACE</p>
          <h2 className="font-black mt-3" style={{ fontSize: "clamp(2rem, 4vw, 3rem)", letterSpacing: "-1px" }}>
            Manage Your Positions
          </h2>
          <p style={{ color: "#4A6FA5", marginTop: 12, maxWidth: 520, marginLeft: "auto", marginRight: "auto", lineHeight: 1.7, fontSize: "0.95rem" }}>
            Deposit USDC and earn. When your position is out of range, we automatically route your capital to earn real yield. All passive, all on-chain.
          </p>
        </div>

        {!isConnected ? (
          <div style={{
            background: "linear-gradient(135deg, rgba(8,15,30,0.95), rgba(5,10,20,0.95))",
            border: "1px solid rgba(0,102,255,0.2)",
            borderRadius: 20,
            padding: "48px 32px",
            textAlign: "center",
            maxWidth: 480,
            margin: "0 auto",
          }}>
            <div style={{ fontSize: "3rem", marginBottom: 16, opacity: 0.5 }}>⬡</div>
            <h3 style={{ fontWeight: 800, fontSize: "1.2rem", marginBottom: 8 }}>Connect Your Wallet</h3>
            <p style={{ color: "#4A6FA5", fontSize: "0.875rem", marginBottom: 28, lineHeight: 1.6 }}>
              Connect to Unichain Sepolia to deposit USDC and view your live positions.
            </p>
            <div style={{ display: "inline-block" }}>
              <WalletButton />
            </div>
          </div>
        ) : (
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(340px, 1fr))", gap: 24 }}>
            <DepositForm onDeposited={() => setRefreshKey((k) => k + 1)} />
            <MyPositions refreshKey={refreshKey} />
          </div>
        )}
      </div>
    </section>
  );
}

export default function Home() {
  return (
    <div className="min-h-screen" style={{ backgroundColor: "#050A14", color: "#F0F4FF" }}>
      {/* Skip to main content: keyboard accessibility */}
      <a href="#main-content" className="skip-to-content">Skip to main content</a>

      {/* ── Nav ─────────────────────────────────────────── */}
      <nav className="fixed top-0 left-0 right-0 z-50 flex items-center justify-between px-8 py-4"
        style={{ background: "rgba(5,10,20,0.85)", backdropFilter: "blur(16px)", borderBottom: "1px solid rgba(0,102,255,0.12)" }}>
        <div className="flex items-center gap-3">
          <Image src="/logo.svg" alt="StableStream" width={36} height={36} priority/>
          <span style={{ fontWeight: 700, fontSize: "1.1rem", letterSpacing: "-0.5px" }}>
            Stable<span style={{ color: "#00AAFF" }}>Stream</span>
          </span>
        </div>
        <div className="hidden md:flex items-center gap-8" style={{ fontSize: "0.875rem", color: "#4A6FA5" }}>
          <a href="#features" className="hover:text-white transition-colors">Features</a>
          <a href="#architecture" className="hover:text-white transition-colors">Architecture</a>
          <a href="#app" className="hover:text-white transition-colors">App</a>
          <a href="#contracts" className="hover:text-white transition-colors">Contracts</a>
          <a href="https://github.com/Majormaxx/stablestream" target="_blank" rel="noopener noreferrer"
            className="hover:text-white transition-colors">GitHub</a>
        </div>
        <WalletButton />
      </nav>

      {/* ── Hero ─────────────────────────────────────────── */}
      <section id="main-content" className="relative flex flex-col items-center justify-center text-center min-h-screen pt-20 px-6 overflow-hidden">

        {/* Grid background */}
        <div className="absolute inset-0 pointer-events-none" style={{
          backgroundImage: "linear-gradient(rgba(0,102,255,0.05) 1px, transparent 1px), linear-gradient(90deg, rgba(0,102,255,0.05) 1px, transparent 1px)",
          backgroundSize: "64px 64px",
        }}/>

        {/* Radial glow */}
        <div className="absolute inset-0 pointer-events-none" style={{
          background: "radial-gradient(ellipse 80% 60% at 50% 40%, rgba(0,102,255,0.12) 0%, transparent 70%)"
        }}/>

        <div className="relative z-10 max-w-4xl mx-auto">
          {/* Badge */}
          <div className="fade-up inline-flex items-center gap-2 mb-8 px-4 py-2 rounded-full"
            style={{ border: "1px solid rgba(0,170,255,0.3)", background: "rgba(0,102,255,0.08)", fontSize: "0.8rem", color: "#00AAFF", letterSpacing: "1px", fontWeight: 600 }}>
            <span style={{ width: 6, height: 6, borderRadius: "50%", background: "#00D4FF", display: "inline-block" }}
              className="stream-pulse"/>
            DYNAMIC STABLECOIN MANAGER · UNISWAP v4 HOOKATHON · REACTIVE NETWORK
          </div>

          {/* Headline */}
          <h1 className="fade-up-delay-1 font-black tracking-tight mb-6"
            style={{ fontSize: "clamp(2.8rem, 7vw, 5.5rem)", lineHeight: 1.05, letterSpacing: "-2px" }}>
            Your Liquidity,<br/>
            <span className="gradient-text">Always at Work.</span>
          </h1>

          {/* Sub */}
          <p className="fade-up-delay-2 max-w-2xl mx-auto mb-10"
            style={{ fontSize: "clamp(1rem, 2vw, 1.25rem)", color: "#4A6FA5", lineHeight: 1.7 }}>
            A <strong style={{ color: "#00AAFF" }}>Dynamic Stablecoin Manager</strong> built as a Uniswap v4 hook.
            Out-of-range USDC earns yield via Compound V3 — recalled just-in-time by a{" "}
            <strong style={{ color: "#00C864" }}>Reactive Network RSC</strong> with zero off-chain infrastructure.
            Each position is an <strong style={{ color: "#FFB800" }}>on-chain NFT</strong>.
          </p>

          {/* CTAs */}
          <div className="fade-up-delay-3 flex flex-wrap gap-4 justify-center">
            <a href="#contracts"
              style={{ background: "linear-gradient(135deg, #0066FF, #00AAFF)", borderRadius: "12px", padding: "14px 32px", fontWeight: 700, fontSize: "1rem", color: "#fff", boxShadow: "0 8px 32px rgba(0,102,255,0.35)" }}>
              View Deployed Contracts →
            </a>
            <a href="#features"
              style={{ border: "1px solid rgba(0,170,255,0.3)", borderRadius: "12px", padding: "14px 32px", fontWeight: 600, fontSize: "1rem", color: "#00AAFF", background: "rgba(0,102,255,0.06)" }}>
              How It Works
            </a>
          </div>
        </div>

        {/* Logo mark centered below */}
        <div className="fade-up-delay-4 relative mt-20">
          <div style={{ width: 160, height: 160, filter: "drop-shadow(0 0 48px rgba(0,102,255,0.5))" }}>
            <Image src="/logo.svg" alt="StableStream mark" width={160} height={160} className="stream-pulse"/>
          </div>
        </div>
      </section>

      {/* ── Stats ─────────────────────────────────────────── */}
      <section style={{ borderTop: "1px solid rgba(0,102,255,0.12)", borderBottom: "1px solid rgba(0,102,255,0.12)", background: "rgba(8,15,30,0.6)" }}
        className="py-16 px-6">
        <div className="max-w-5xl mx-auto grid grid-cols-2 md:grid-cols-4 gap-8 text-center">
          <LiveHeroStats />
        </div>
      </section>

      {/* ── Features ─────────────────────────────────────── */}
      <section id="features" className="py-28 px-6">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <p style={{ color: "#00AAFF", fontWeight: 600, fontSize: "0.8rem", letterSpacing: "2px" }}>PROTOCOL FEATURES</p>
            <h2 className="font-black mt-3" style={{ fontSize: "clamp(2rem, 4vw, 3rem)", letterSpacing: "-1px" }}>
              Built for Capital Efficiency
            </h2>
            <p style={{ color: "#4A6FA5", marginTop: 12, maxWidth: 480, marginLeft: "auto", marginRight: "auto", lineHeight: 1.7 }}>
              Every component of StableStream is designed to eliminate idle capital and maximise yield. Autonomously, trustlessly, on-chain.
            </p>
          </div>
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
            {features.map((f) => (
              <div key={f.title} className="card-hover rounded-2xl p-6 border-glow">
                <div className="mb-4">{f.icon}</div>
                <h3 style={{ fontWeight: 700, fontSize: "1.05rem", marginBottom: 8 }}>{f.title}</h3>
                <p style={{ color: "#4A6FA5", fontSize: "0.875rem", lineHeight: 1.7 }}>{f.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── Architecture ─────────────────────────────────── */}
      <section id="architecture" style={{ background: "rgba(8,15,30,0.6)", borderTop: "1px solid rgba(0,102,255,0.1)", borderBottom: "1px solid rgba(0,102,255,0.1)" }}
        className="py-28 px-6">
        <div className="max-w-5xl mx-auto">
          <div className="text-center mb-16">
            <p style={{ color: "#00AAFF", fontWeight: 600, fontSize: "0.8rem", letterSpacing: "2px" }}>SYSTEM ARCHITECTURE</p>
            <h2 className="font-black mt-3" style={{ fontSize: "clamp(2rem, 4vw, 3rem)", letterSpacing: "-1px" }}>
              How StableStream Works
            </h2>
          </div>
          <div className="flex flex-col gap-4">
            {[
              { step: "01", color: "#0066FF", title: "Position Created", desc: "You add liquidity to Uniswap. We mint an NFT that tracks your position and ongoing yield." },
              { step: "02", color: "#00AAFF", title: "Price Exits Range", desc: "When the market moves and your position temporarily leaves the trading range, our system detects this instantly." },
              { step: "03", color: "#00D4FF", title: "Yield Activates", desc: "Your idle capital automatically shifts to the highest-paying yield source (Compound or Aave). Earning starts now." },
              { step: "04", color: "#FFB800", title: "Price Returns", desc: "When the market swings back, your capital returns automatically—ready to earn trading fees again." },
            ].map((step) => (
              <div key={step.step} className="flex items-start gap-6 rounded-2xl p-6 card-hover"
                style={{ border: "1px solid rgba(0,102,255,0.15)", background: "rgba(5,10,20,0.6)" }}>
                <div style={{ fontSize: "1.8rem", fontWeight: 900, color: step.color, minWidth: 56, letterSpacing: "-1px", opacity: 0.9 }}>{step.step}</div>
                <div>
                  <div style={{ fontWeight: 700, fontSize: "1.05rem", marginBottom: 4 }}>{step.title}</div>
                  <div style={{ color: "#4A6FA5", fontSize: "0.875rem", lineHeight: 1.7 }}>{step.desc}</div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>


      {/* ── App: Deposit & Positions ─────────────────────── */}
      <AppSection />

      {/* ── Protocol Dashboard (live contract reads) ─────── */}
      <Suspense fallback={<SectionSkeleton height={280} />}>
        <ProtocolStats />
      </Suspense>

      {/* ── Hook & Router Status ─────────────────────────── */}
      <Suspense fallback={<SectionSkeleton height={380} />}>
        <HookStatus />
      </Suspense>

      {/* ── Contract Explorer ────────────────────────────── */}
      <Suspense fallback={<SectionSkeleton height={320} />}>
        <ContractExplorer />
      </Suspense>

      {/* ── Footer ───────────────────────────────────────── */}
      <footer style={{ borderTop: "1px solid rgba(0,102,255,0.12)", padding: "40px 24px" }} className="text-center">
        <div className="flex items-center justify-center gap-3 mb-4">
          <Image src="/logo.svg" alt="StableStream" width={28} height={28}/>
          <span style={{ fontWeight: 700, color: "#F0F4FF" }}>Stable<span style={{ color: "#00AAFF" }}>Stream</span></span>
        </div>
        <p style={{ color: "#4A6FA5", fontSize: "0.8rem", letterSpacing: "0.5px" }}>
          Built for the Uniswap v4 Hookathon · Deployed on Unichain Sepolia · Powered by Reactive Network
        </p>
      </footer>

    </div>
  );
}
