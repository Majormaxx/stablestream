"use client";

import { LiveHeroStats } from "@/components/LiveHeroStats";
import { useInView } from "@/lib/useInView";

export function StatsBar() {
  const { ref, inView } = useInView();

  return (
    <div ref={ref} className={`border-y border-brand-500/12 bg-bg-card/60 py-16 px-6 transition-all duration-700 ${inView ? "opacity-100 translate-y-0" : "opacity-0 translate-y-6"}`}>
      <div className="max-w-5xl mx-auto grid grid-cols-2 md:grid-cols-4 gap-8 text-center">
        <LiveHeroStats />
      </div>
    </div>
  );
}
