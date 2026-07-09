"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import { WalletButton } from "@/components/WalletButton";
import { DepositForm } from "@/components/DepositForm";
import { MyPositions } from "@/components/MyPositions";

export function AppSection() {
  const { isConnected } = useAccount();
  const [refreshKey, setRefreshKey] = useState(0);

  return (
    <section id="app" className="py-28 px-6" style={{ borderTop: "1px solid rgba(0,102,255,0.1)" }}>
      <div className="max-w-5xl mx-auto">
        <div className="text-center mb-12">
          <p className="text-brand-400 font-semibold text-[0.8rem] tracking-[2px]">PROTOCOL INTERFACE</p>
          <h2 className="font-black mt-3 text-[clamp(2rem,4vw,3rem)] -tracking-[1px]">
            Manage Your Positions
          </h2>
          <p className="text-text-muted mt-3 max-w-[520px] mx-auto leading-[1.7] text-[0.95rem]">
            Deposit USDC and earn. When your position is out of range, we automatically route your capital to earn real yield. All passive, all on-chain.
          </p>
        </div>

        {!isConnected ? (
          <div className="bg-bg-card/95 border border-brand-500/20 rounded-[20px] p-[48px_32px] text-center max-w-[480px] mx-auto">
            <div className="text-[3rem] mb-4 opacity-50">⬡</div>
            <h3 className="font-extrabold text-[1.2rem] mb-2">Connect Your Wallet</h3>
            <p className="text-text-muted text-[0.875rem] mb-7 leading-[1.6]">
              Connect to Unichain Sepolia to deposit USDC and view your live positions.
            </p>
            <div className="inline-block">
              <WalletButton />
            </div>
          </div>
        ) : (
          <div className="grid grid-cols-[repeat(auto-fit,minmax(340px,1fr))] gap-6">
            <DepositForm onDeposited={() => setRefreshKey((k) => k + 1)} />
            <MyPositions refreshKey={refreshKey} />
          </div>
        )}
      </div>
    </section>
  );
}
