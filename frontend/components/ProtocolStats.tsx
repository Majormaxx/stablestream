"use client";

import { useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import {
  CONTRACTS,
  POOL_ID,
  CompoundV3AdapterABI,
  YieldRouterABI,
  StableStreamHookABI,
} from "@/lib/contracts";
import { USDC_DECIMALS } from "@/lib/poolKey";
import { Card } from "@/components/ui/Card";
import { StatValue } from "@/components/ui/StatValue";

export function ProtocolStats() {
  const { data, isLoading } = useReadContracts({
    contracts: [
      {
        address: CONTRACTS.COMPOUND_ADAPTER,
        abi: CompoundV3AdapterABI,
        functionName: "currentAPY",
      },
      {
        address: CONTRACTS.YIELD_ROUTER,
        abi: YieldRouterABI,
        functionName: "sourceCount",
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
      {
        address: CONTRACTS.HOOK,
        abi: StableStreamHookABI,
        functionName: "getDynamicFee",
        args: [POOL_ID as `0x${string}`],
      },
    ],
    query: { refetchInterval: 20_000 },
  });

  const [apyR, sourceR, totalCapR, yieldCapR, dynFeeR] = data ?? [];

  const apyBps   = apyR?.status === "success" ? Number(apyR.result) : null;
  const apyStr   = apyBps != null ? `${(apyBps / 100).toFixed(2)}%` : undefined;

  const srcStr   = sourceR?.status === "success" ? String(sourceR.result) : undefined;

  const totalCap = totalCapR?.status === "success" ? (totalCapR.result as bigint) : null;
  const yieldCap = yieldCapR?.status === "success" ? (yieldCapR.result as bigint) : null;

  const totalStr = totalCap != null
    ? `$${parseFloat(formatUnits(totalCap, USDC_DECIMALS)).toFixed(2)}`
    : undefined;

  const yieldStr = yieldCap != null
    ? `$${parseFloat(formatUnits(yieldCap, USDC_DECIMALS)).toFixed(2)}`
    : undefined;

  const utilPct = totalCap != null && yieldCap != null && totalCap > 0n
    ? `${((Number(yieldCap) / Number(totalCap)) * 100).toFixed(1)}%`
    : totalCap === 0n ? "0.0%" : undefined;

  const dynFeeRaw = dynFeeR?.status === "success" ? Number(dynFeeR.result as bigint) : null;
  const dynFeeStr = dynFeeRaw != null
    ? dynFeeRaw === 0 ? "Base (0 bps)" : `${(dynFeeRaw / 100).toFixed(0)} bps`
    : undefined;

  const statCards = [
    {
      id: "compound-apy",
      label: "Compound V3 APY",
      value: apyStr,
      sub: "Live on-chain read · auto-routes idle capital",
      accent: "linear-gradient(135deg, #E8A33D, #D4892A)",
      loading: isLoading,
      error: apyR?.status === "failure",
    },
    {
      id: "total-capital",
      label: "Total Pool Capital",
      value: totalStr,
      sub: "USDC managed by hook",
      loading: isLoading,
      error: totalCapR?.status === "failure",
    },
    {
      id: "capital-in-yield",
      label: "Capital in Yield",
      value: yieldStr,
      sub: utilPct ? `${utilPct} utilisation · Compound V3` : "USDC earning via Compound V3",
      accent: "linear-gradient(135deg, #3EC9B0, #2DAF9A)",
      loading: isLoading,
      error: yieldCapR?.status === "failure",
    },
    {
      id: "dynamic-fee",
      label: "Dynamic Swap Fee",
      value: dynFeeStr,
      sub: "Scales with yield utilisation · DynamicFeeModule",
      accent: "linear-gradient(135deg, #8A9490, #E8A33D)",
      loading: isLoading,
      error: dynFeeR?.status === "failure",
    },
    {
      id: "yield-sources",
      label: "Yield Sources",
      value: srcStr,
      sub: "Registered adapters · pluggable",
      accent: "linear-gradient(135deg, #E8A33D, #3EC9B0)",
      loading: isLoading,
      error: sourceR?.status === "failure",
    },
  ];

  return (
    <section aria-labelledby="dashboard-heading" className="px-6 py-16 border-t border-rail/60">
      <div className="max-w-[1100px] mx-auto">
        <p className="text-signal font-mono text-[0.7rem] tracking-[2px] text-center mb-2">
          LIVE PROTOCOL DATA · UNICHAIN SEPOLIA · REFRESHES EVERY 20s
        </p>
        <h2
          id="dashboard-heading"
          className="text-center font-black text-[clamp(1.6rem,3vw,2.4rem)] -tracking-[1px] mb-8 font-display"
        >
          Protocol Dashboard
        </h2>
        <div className="flex gap-4 flex-wrap" role="list">
          {statCards.map((s) => (
            <Card key={s.id} className="flex-1 min-w-[160px]">
              <div
                className="text-[2rem] font-black -tracking-[1px] min-h-[2.4rem]"
                style={{
                  background: s.error ? "none" : (s.accent ?? "linear-gradient(135deg, #E8A33D, #D4892A)"),
                  WebkitBackgroundClip: s.error ? "unset" : "text",
                  WebkitTextFillColor: s.error ? "var(--color-error, #D9634B)" : "transparent",
                  color: s.error ? "var(--color-error, #D9634B)" : undefined,
                }}
              >
                <StatValue loading={s.loading} error={s.error} value={s.value} />
              </div>
              <div className="font-bold text-[0.85rem] text-paper mt-1">{s.label}</div>
              <div className={`text-[0.72rem] mt-0.5 ${s.error ? "text-error" : "text-slate"}`}>
                {s.error ? "Failed to load" : s.sub}
              </div>
            </Card>
          ))}
        </div>
      </div>
    </section>
  );
}
