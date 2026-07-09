"use client";

import { Suspense } from "react";
import { Nav } from "@/components/sections/Nav";
import { Hero } from "@/components/sections/Hero";
import { StatsBar } from "@/components/sections/StatsBar";
import { Features } from "@/components/sections/Features";
import { ArchitectureSteps } from "@/components/sections/ArchitectureSteps";
import { VerifiedOnChain } from "@/components/sections/VerifiedOnChain";
import { ModuleSection } from "@/components/sections/ModuleSection";
import { WhyNotBuildYourOwn } from "@/components/sections/WhyNotBuildYourOwn";
import { AppSection } from "@/components/sections/AppSection";
import { ProtocolStats } from "@/components/ProtocolStats";
import { HookStatus } from "@/components/HookStatus";
import { ContractExplorer } from "@/components/ContractExplorer";
import { Footer } from "@/components/sections/Footer";

function SectionSkeleton({ height = 280 }: { height?: number }) {
  return (
    <div
      aria-busy="true"
      aria-label="Loading section"
      className="mx-6 rounded-[var(--radius-panel)] bg-gradient-to-r from-signal/6 via-signal/10 to-signal/6 bg-[length:200%_100%] animate-[shimmer_1.5s_infinite]"
      style={{ height }}
    />
  );
}

export default function Home() {
  return (
    <div className="min-h-screen bg-ink text-paper">
      <a href="#main-content" className="skip-to-content">Skip to main content</a>
      <Nav />
      <Hero />
      <StatsBar />
      <Features />
      <ArchitectureSteps />
      <VerifiedOnChain />
      <ModuleSection />
      <WhyNotBuildYourOwn />

      {/* ── FOR LIQUIDITY PROVIDERS ── */}
      <div className="audience-rule">
        <span className="audience-label">For Liquidity Providers</span>
      </div>

      <AppSection />
      <Suspense fallback={<SectionSkeleton height={280} />}>
        <ProtocolStats />
      </Suspense>
      <Suspense fallback={<SectionSkeleton height={380} />}>
        <HookStatus />
      </Suspense>
      <Suspense fallback={<SectionSkeleton height={320} />}>
        <ContractExplorer />
      </Suspense>
      <Footer />
    </div>
  );
}
