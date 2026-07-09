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
import { StatValue } from "@/components/ui/StatValue";

interface StatDef {
  value: string;
  label: string;
  sub: string;
}

function fmtUsdc(raw: bigint): string {
  const n = parseFloat(formatUnits(raw, USDC_DECIMALS));
  if (n >= 1_000_000) return `$${(n / 1_000_000).toFixed(2)}M`;
  if (n >= 1_000)     return `$${(n / 1_000).toFixed(1)}K`;
  return `$${n.toFixed(2)}`;
}

function fmtApy(bps: number): string {
  return `${(bps / 100).toFixed(2)}%`;
}

const STATIC_STATS: StatDef[] = [
  { value: "v4",  label: "Uniswap Hook",       sub: "Native v4 · zero overhead" },
  { value: "RSC", label: "Reactive Automation", sub: "Lasna chain · JIT recall" },
  { value: "NFT", label: "LP Positions",        sub: "Non-fungible · on-chain" },
];

export function LiveHeroStats() {
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
    ],
    query: { refetchInterval: 20_000 },
  });

  const [apyR, totalCapR] = data ?? [];

  const apyBps  = apyR?.status === "success" ? Number(apyR.result as bigint) : null;
  const totalCap = totalCapR?.status === "success" ? (totalCapR.result as bigint) : null;

  const liveStats: StatDef[] = [
    {
      value: apyBps != null ? fmtApy(apyBps) : "—",
      label: "Yield APY",
      sub: "Compound V3 · auto-routes idle USDC",
    },
    {
      value: totalCap != null ? fmtUsdc(totalCap) : "—",
      label: "Pool Capital",
      sub: "USDC managed by hook",
    },
  ];

  const allStats = [...liveStats, ...STATIC_STATS];

  return (
    <>
      {allStats.map((s) => (
        <div key={s.label}>
          <div className="text-[2.8rem] font-black -tracking-[2px] bg-gradient-to-br from-brand-400 to-cyan-400 bg-clip-text text-transparent min-h-[3.2rem]">
            <StatValue loading={isLoading} value={s.value} />
          </div>
          <div className="font-bold text-[0.9rem] text-text-primary mt-1">
            {s.label}
          </div>
          <div className="text-[0.75rem] text-text-muted mt-0.5">
            {s.sub}
          </div>
        </div>
      ))}
    </>
  );
}
