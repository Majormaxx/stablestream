"use client";

import { Suspense } from "react";
import { Nav } from "@/components/sections/Nav";
import { Hero } from "@/components/sections/Hero";
import { StatsBar } from "@/components/sections/StatsBar";
import { Features } from "@/components/sections/Features";
import { ArchitectureSteps } from "@/components/sections/ArchitectureSteps";
import { ModuleSection } from "@/components/sections/ModuleSection";
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
      className="mx-6 rounded-[16px] bg-gradient-to-r from-brand-500/6 via-brand-400/10 to-brand-500/6 bg-[length:200%_100%] animate-[shimmer_1.5s_infinite]"
      style={{ height }}
    />
  );
}

export default function Home() {
  return (
    <div className="min-h-screen bg-bg-deep text-text-primary">
      <a href="#main-content" className="skip-to-content">Skip to main content</a>
      <Nav />
      <Hero />
      <StatsBar />
      <Features />
      <ArchitectureSteps />
      <ModuleSection />
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
