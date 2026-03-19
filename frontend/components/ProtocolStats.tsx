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

function Skeleton({ width = "5rem" }: { width?: string }) {
  return (
    <span
      aria-hidden="true"
      style={{
        display: "inline-block",
        width,
        height: "2rem",
        borderRadius: 6,
        background: "linear-gradient(90deg, rgba(0,102,255,0.12) 25%, rgba(0,170,255,0.18) 50%, rgba(0,102,255,0.12) 75%)",
        backgroundSize: "200% 100%",
        animation: "shimmer 1.5s infinite",
        verticalAlign: "middle",
      }}
    />
  );
}

function StatCard({
  label, value, sub, accent, loading, error,
}: {
  label: string;
  value?: string;
  sub?: string;
  accent?: string;
  loading?: boolean;
  error?: boolean;
}) {
  return (
    <div
      role="region"
      aria-label={label}
      style={{
        border: "1px solid rgba(0,102,255,0.18)",
        background: "rgba(8,15,30,0.8)",
        borderRadius: 16,
        padding: "24px 28px",
        flex: 1,
        minWidth: 160,
      }}
    >
      <div style={{
        fontSize: "2rem", fontWeight: 900, letterSpacing: "-1px", minHeight: "2.4rem",
        background: error ? "none" : (accent ?? "linear-gradient(135deg, #00AAFF, #00D4FF)"),
        WebkitBackgroundClip: error ? "unset" : "text",
        WebkitTextFillColor: error ? "#FF6B6B" : "transparent",
        color: error ? "#FF6B6B" : undefined,
      }}>
        {loading ? <Skeleton /> : error ? "Error" : (value ?? "—")}
      </div>
      <div style={{ fontWeight: 700, fontSize: "0.85rem", color: "#F0F4FF", marginTop: 4 }}>{label}</div>
      {sub && (
        <div style={{ fontSize: "0.72rem", color: error ? "#FF6B6B" : "#4A6FA5", marginTop: 2 }}>
          {error ? "Failed to load" : sub}
        </div>
      )}
    </div>
  );
}

export function ProtocolStats() {
  // Single multicall — 4 reads, one round-trip, one loading state
  const { data, isLoading } = useReadContracts({
    contracts: [
      {
        // currentAPY() → uint256 basis points (250 = 2.50%)
        address: CONTRACTS.COMPOUND_ADAPTER,
        abi: CompoundV3AdapterABI,
        functionName: "currentAPY",
      },
      {
        // sourceCount() → uint256 number of registered yield adapters
        address: CONTRACTS.YIELD_ROUTER,
        abi: YieldRouterABI,
        functionName: "sourceCount",
      },
      {
        // poolTotalCapital(bytes32) → uint256 USDC tracked in pool (6 dec)
        address: CONTRACTS.HOOK,
        abi: StableStreamHookABI,
        functionName: "poolTotalCapital",
        args: [POOL_ID as `0x${string}`],
      },
      {
        // poolYieldCapital(bytes32) → uint256 USDC currently in yield (6 dec)
        address: CONTRACTS.HOOK,
        abi: StableStreamHookABI,
        functionName: "poolYieldCapital",
        args: [POOL_ID as `0x${string}`],
      },
      {
        // getDynamicFee(bytes32) → uint24 current swap fee bps
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

  // Yield utilisation %: how much of pool capital is currently earning yield
  const utilPct = totalCap != null && yieldCap != null && totalCap > 0n
    ? `${((Number(yieldCap) / Number(totalCap)) * 100).toFixed(1)}%`
    : totalCap === 0n ? "0.0%" : undefined;

  // Dynamic fee: uint24 raw value — divide by 10000 for bps display
  const dynFeeRaw = dynFeeR?.status === "success" ? Number(dynFeeR.result as bigint) : null;
  const dynFeeStr = dynFeeRaw != null
    ? dynFeeRaw === 0 ? "Base (0 bps)" : `${(dynFeeRaw / 100).toFixed(0)} bps`
    : undefined;

  return (
    <section aria-labelledby="dashboard-heading" style={{ padding: "64px 24px" }}>
      <div style={{ maxWidth: 1100, margin: "0 auto" }}>
        <p style={{ color: "#00AAFF", fontWeight: 600, fontSize: "0.75rem", letterSpacing: "2px", textAlign: "center", marginBottom: 8 }}>
          LIVE PROTOCOL DATA · UNICHAIN SEPOLIA · REFRESHES EVERY 20s
        </p>
        <h2
          id="dashboard-heading"
          style={{ textAlign: "center", fontWeight: 900, fontSize: "clamp(1.6rem,3vw,2.4rem)", letterSpacing: "-1px", marginBottom: 32 }}
        >
          Protocol Dashboard
        </h2>
        <div style={{ display: "flex", gap: 16, flexWrap: "wrap" }} role="list">
          <StatCard
            label="Compound V3 APY"
            value={apyStr}
            sub="Live on-chain read · auto-routes idle capital"
            accent="linear-gradient(135deg, #FFB800, #FF8C00)"
            loading={isLoading}
            error={apyR?.status === "failure"}
          />
          <StatCard
            label="Total Pool Capital"
            value={totalStr}
            sub="USDC managed by hook"
            loading={isLoading}
            error={totalCapR?.status === "failure"}
          />
          <StatCard
            label="Capital in Yield"
            value={yieldStr}
            sub={utilPct ? `${utilPct} utilisation · Compound V3` : "USDC earning via Compound V3"}
            accent="linear-gradient(135deg, #00C864, #00AAFF)"
            loading={isLoading}
            error={yieldCapR?.status === "failure"}
          />
          <StatCard
            label="Dynamic Swap Fee"
            value={dynFeeStr}
            sub="Scales with yield utilisation · DynamicFeeModule"
            accent="linear-gradient(135deg, #7c3aed, #06b6d4)"
            loading={isLoading}
            error={dynFeeR?.status === "failure"}
          />
          <StatCard
            label="Yield Sources"
            value={srcStr}
            sub="Registered adapters · pluggable"
            accent="linear-gradient(135deg, #0066FF, #00AAFF)"
            loading={isLoading}
            error={sourceR?.status === "failure"}
          />
        </div>
      </div>
    </section>
  );
}
