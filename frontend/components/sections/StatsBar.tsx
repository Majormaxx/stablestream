"use client";

import { useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import {
  CONTRACTS,
  POOL_ID,
  CompoundV3AdapterABI,
  StableStreamHookABI,
} from "@/lib/contracts";
import { USDC_DECIMALS } from "@/lib/poolKey";
import { useInView } from "@/lib/useInView";

function stripValue(val: string | null, loading: boolean, error: boolean) {
  if (error) return <span className="text-error">—</span>;
  if (loading) return <span className="text-slate">—</span>;
  return <span>{val}</span>;
}

export function StatsBar() {
  const { ref, inView } = useInView();

  const { data, isLoading } = useReadContracts({
    contracts: [
      {
        address: CONTRACTS.COMPOUND_ADAPTER,
        abi: CompoundV3AdapterABI,
        functionName: "currentAPY",
      },
      {
        address: CONTRACTS.HOOK,
        abi: StableStreamHookABI,
        functionName: "poolTotalCapital",
        args: [POOL_ID as `0x${string}`],
      },
      {
        address: CONTRACTS.HOOK,
        abi: StableStreamHookABI,
        functionName: "poolYieldCapital",
        args: [POOL_ID as `0x${string}`],
      },
    ],
    query: { refetchInterval: 20_000 },
  });

  const [apyR, totalCapR, yieldCapR] = data ?? [];

  const apyBps   = apyR?.status === "success" ? Number(apyR.result) : null;
  const apyStr   = apyBps != null ? `${(apyBps / 100).toFixed(2)}%` : null;
  const totalCap = totalCapR?.status === "success" ? (totalCapR.result as bigint) : null;
  const yieldCap = yieldCapR?.status === "success" ? (yieldCapR.result as bigint) : null;
  const totalStr = totalCap != null ? `$${parseFloat(formatUnits(totalCap, USDC_DECIMALS)).toFixed(2)}` : null;
  const yieldStr = yieldCap != null ? `$${parseFloat(formatUnits(yieldCap, USDC_DECIMALS)).toFixed(2)}` : null;
  const apyError = apyR?.status === "failure";
  const totalError = totalCapR?.status === "failure";
  const yieldError = yieldCapR?.status === "failure";

  return (
    <div
      ref={ref}
      className={`border-y border-rail/60 bg-channel/30 py-5 px-6 transition-all duration-700 ${inView ? "opacity-100" : "opacity-0"}`}
    >
      <div className="max-w-4xl mx-auto instrument-strip justify-center">
        <div className="instrument-item">
          <div className="instrument-value">
            <div className="text-[0.7rem] font-mono tracking-[1px] text-slate uppercase mb-1">TVL</div>
            {stripValue(totalStr, isLoading, totalError)}
          </div>
        </div>
        <div className="instrument-divider" />
        <div className="instrument-item">
          <div className="instrument-value">
            <div className="text-[0.7rem] font-mono tracking-[1px] text-slate uppercase mb-1">Yield APY</div>
            {stripValue(apyStr, isLoading, apyError)}
          </div>
        </div>
        <div className="instrument-divider" />
        <div className="instrument-item">
          <div className="instrument-value">
            <div className="text-[0.7rem] font-mono tracking-[1px] text-slate uppercase mb-1">In Yield</div>
            {stripValue(yieldStr, isLoading, yieldError)}
          </div>
        </div>
        <div className="instrument-divider" />
        <div className="instrument-item">
          <div className="instrument-value">
            <div className="text-[0.7rem] font-mono tracking-[1px] text-slate uppercase mb-1">Active Source</div>
            <span>Compound V3</span>
          </div>
        </div>
        <div className="instrument-divider" />
        <div className="instrument-item">
          <div className="instrument-value">
            <div className="text-[0.7rem] font-mono tracking-[1px] text-slate uppercase mb-1">Automation</div>
            <span className="flex items-center gap-1.5">
              <span className="inline-block w-[5px] h-[5px] rounded-full bg-current stream-pulse" />
              Reactive Network
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
