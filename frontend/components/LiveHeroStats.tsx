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

/* ── Stat shape ─────────────────────────────────────────── */
interface StatDef {
  value: string;
  label: string;
  sub: string;
}

/* ── Helpers ─────────────────────────────────────────────── */
function fmtUsdc(raw: bigint): string {
  const n = parseFloat(formatUnits(raw, USDC_DECIMALS));
  if (n >= 1_000_000) return `$${(n / 1_000_000).toFixed(2)}M`;
  if (n >= 1_000)     return `$${(n / 1_000).toFixed(1)}K`;
  return `$${n.toFixed(2)}`;
}

function fmtApy(bps: number): string {
  return `${(bps / 100).toFixed(2)}%`;
}

/* ── Static badge stats (never change) ──────────────────── */
const STATIC_STATS: StatDef[] = [
  { value: "v4",  label: "Uniswap Hook",       sub: "Native v4 · zero overhead" },
  { value: "RSC", label: "Reactive Automation", sub: "Lasna chain · JIT recall" },
  { value: "NFT", label: "LP Positions",        sub: "Non-fungible · on-chain" },
];

/* ── Component ───────────────────────────────────────────── */
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
      value: isLoading ? "…" : apyBps != null ? fmtApy(apyBps) : "—",
      label: "Yield APY",
      sub: "Compound V3 · auto-routes idle USDC",
    },
    {
      value: isLoading ? "…" : totalCap != null ? fmtUsdc(totalCap) : "—",
      label: "Pool Capital",
      sub: "USDC managed by hook",
    },
  ];

  const allStats = [...liveStats, ...STATIC_STATS];

  return (
    <>
      {allStats.map((s) => (
        <div key={s.label}>
          <div
            style={{
              fontSize: "2.8rem",
              fontWeight: 900,
              letterSpacing: "-2px",
              background: "linear-gradient(135deg, #00AAFF, #00D4FF)",
              WebkitBackgroundClip: "text",
              WebkitTextFillColor: "transparent",
              minHeight: "3.2rem",
            }}
          >
            {s.value}
          </div>
          <div style={{ fontWeight: 700, fontSize: "0.9rem", color: "#F0F4FF", marginTop: 4 }}>
            {s.label}
          </div>
          <div style={{ fontSize: "0.75rem", color: "#4A6FA5", marginTop: 2 }}>
            {s.sub}
          </div>
        </div>
      ))}
    </>
  );
}
