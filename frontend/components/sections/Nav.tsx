"use client";

import Image from "next/image";
import { WalletButton } from "@/components/WalletButton";

export function Nav() {
  return (
    <nav className="fixed top-0 left-0 right-0 z-50 flex items-center justify-between px-8 py-4"
      style={{ background: "rgba(12,15,13,0.9)", backdropFilter: "blur(16px)", borderBottom: "1px solid rgba(232,163,61,0.12)" }}>
      <div className="flex items-center gap-3">
        <Image src="/logo.svg" alt="StableStream" width={36} height={36} priority/>
        <span className="font-bold text-[1.1rem] -tracking-[0.5px] font-display">
          Stable<span className="text-signal">Stream</span>
        </span>
      </div>
      <div className="hidden md:flex items-center gap-8 text-[0.875rem] text-slate">
        <a href="#features" className="hover:text-paper transition-colors">Features</a>
        <a href="#architecture" className="hover:text-paper transition-colors">Architecture</a>
        <a href="#module" className="hover:text-paper transition-colors">Build on It</a>
        <a href="#app" className="hover:text-paper transition-colors">App</a>
        <a href="#contracts" className="hover:text-paper transition-colors">Contracts</a>
      </div>
      <WalletButton />
    </nav>
  );
}
