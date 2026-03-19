"use client";

import { useState, useEffect } from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { formatUnits } from "viem";
import { CONTRACTS, StableStreamHookABI } from "@/lib/contracts";
import { USDC_DECIMALS } from "@/lib/poolKey";

/* ── Types ──────────────────────────────────────────────── */
interface YieldState {
  depositedPrincipal: bigint;
  harvestedYield: bigint;
  lastRouteTimestamp: bigint;
  _reserved: bigint;
}

interface TrackedPosition {
  owner: `0x${string}`;
  asset: `0x${string}`;
  poolId: `0x${string}`;
  tickLower: number;
  tickUpper: number;
  liquidity: bigint;
  yieldDeposited: bigint;
  activeYieldSource: `0x${string}`;
  yieldState: YieldState;
  closed: boolean;
  key: {
    currency0: `0x${string}`;
    currency1: `0x${string}`;
    fee: number;
    tickSpacing: number;
    hooks: `0x${string}`;
  };
}

const ZERO_ADDR = "0x0000000000000000000000000000000000000000";

function positionStatus(pos: TrackedPosition): { label: string; color: string } {
  if (pos.closed) return { label: "Closed", color: "#FF5050" };
  if (pos.activeYieldSource !== ZERO_ADDR && pos.yieldDeposited > 0n)
    return { label: "Earning Yield", color: "#FFB800" };
  return { label: "In Pool", color: "#00C864" };
}

function truncate(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

/* ── Skeleton ────────────────────────────────────────────── */
function CardSkeleton() {
  return (
    <div style={{
      height: 180, borderRadius: 14,
      backgroundImage: "linear-gradient(90deg, rgba(0,102,255,0.06) 25%, rgba(0,170,255,0.1) 50%, rgba(0,102,255,0.06) 75%)",
      backgroundSize: "200% 100%",
      animation: "shimmer 1.5s infinite",
    }} aria-busy="true" aria-label="Loading position" />
  );
}

/* ── Single position card ────────────────────────────────── */
function PositionCard({
  positionId,
  onWithdrawn,
}: {
  positionId: `0x${string}`;
  onWithdrawn: () => void;
}) {
  const [withdrawing, setWithdrawing]   = useState(false);
  const [withdrawn, setWithdrawn]       = useState(false);
  const [errorMsg, setErrorMsg]         = useState("");

  const { data: rawPos, isLoading } = useReadContract({
    address: CONTRACTS.HOOK,
    abi: StableStreamHookABI,
    functionName: "getPosition",
    args: [positionId],
    query: { refetchInterval: 20_000 },
  });

  const { writeContract: writeWithdraw, isPending: withdrawPending, data: withdrawHash } =
    useWriteContract();

  const { isSuccess: withdrawConfirmed } = useWaitForTransactionReceipt({ hash: withdrawHash });

  /* ── Confirm withdrawal ─────────────────────────────── */
  useEffect(() => {
    if (withdrawConfirmed && withdrawing) {
      setWithdrawn(true);
      setWithdrawing(false);
      onWithdrawn();
    }
  }, [withdrawConfirmed, withdrawing, onWithdrawn]);

  const pos = rawPos as TrackedPosition | undefined;

  function handleWithdraw() {
    setErrorMsg("");
    setWithdrawing(true);
    writeWithdraw(
      { address: CONTRACTS.HOOK, abi: StableStreamHookABI, functionName: "withdraw", args: [positionId] },
      {
        onError: (e) => {
          setErrorMsg(e.message.split("\n")[0]);
          setWithdrawing(false);
        },
      }
    );
  }

  if (isLoading) return <CardSkeleton />;
  if (!pos) return null;

  const status     = positionStatus(pos);
  const yieldFmt   = formatUnits(pos.yieldDeposited, USDC_DECIMALS);
  const harvestFmt = formatUnits(pos.yieldState.harvestedYield, USDC_DECIMALS);
  const isPending  = withdrawPending || withdrawing;

  return (
    <div style={{
      background: "rgba(8,15,30,0.85)",
      border: "1px solid rgba(0,102,255,0.18)",
      borderRadius: 14, padding: "20px",
      display: "flex", flexDirection: "column", gap: 14,
    }}>
      {/* Header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
        <div>
          <div style={{ fontFamily: "monospace", fontSize: "0.72rem", color: "#4A6FA5", marginBottom: 4 }}>
            {truncate(positionId)}
          </div>
          <div style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
            <span style={{ width: 7, height: 7, borderRadius: "50%", background: status.color, display: "inline-block" }} />
            <span style={{ fontWeight: 700, fontSize: "0.85rem", color: status.color }}>{status.label}</span>
          </div>
        </div>
        <div style={{ textAlign: "right" }}>
          <div style={{ fontSize: "0.72rem", color: "#4A6FA5", marginBottom: 2 }}>Ticks</div>
          <div style={{ fontWeight: 700, fontSize: "0.9rem", fontFamily: "monospace", color: "#F0F4FF" }}>
            {pos.tickLower} → {pos.tickUpper}
          </div>
        </div>
      </div>

      {/* Metrics */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8 }}>
        {[
          {
            label: "LIQUIDITY",
            value: pos.liquidity > 0n
              ? pos.liquidity.toString().length > 8
                ? `${(Number(pos.liquidity) / 1e8).toFixed(2)}e8`
                : pos.liquidity.toString()
              : "0",
            color: "#F0F4FF",
          },
          {
            label: "IN YIELD",
            value: `${parseFloat(yieldFmt).toFixed(2)} USDC`,
            color: pos.yieldDeposited > 0n ? "#FFB800" : "#4A6FA5",
          },
          {
            label: "HARVESTED",
            value: `${parseFloat(harvestFmt).toFixed(4)} USDC`,
            color: "#00C864",
          },
        ].map((m) => (
          <div key={m.label} style={{ background: "rgba(0,102,255,0.05)", borderRadius: 10, padding: "10px 10px" }}>
            <div style={{ fontSize: "0.65rem", color: "#4A6FA5", marginBottom: 4, letterSpacing: "0.5px" }}>{m.label}</div>
            <div style={{ fontWeight: 800, fontSize: "0.82rem", color: m.color, fontFamily: "monospace", wordBreak: "break-all" }}>
              {m.value}
            </div>
          </div>
        ))}
      </div>

      {/* Yield source */}
      {pos.activeYieldSource !== ZERO_ADDR && (
        <div style={{ fontSize: "0.74rem", color: "#4A6FA5" }}>
          Routing to:{" "}
          <a href={`https://sepolia.uniscan.xyz/address/${pos.activeYieldSource}`}
            target="_blank" rel="noopener noreferrer"
            style={{ color: "#00AAFF", textDecoration: "none", fontFamily: "monospace" }}
            aria-label="View yield source on Uniscan (opens in new tab)">
            {truncate(pos.activeYieldSource)} ↗
          </a>
        </div>
      )}

      {/* Error */}
      {errorMsg && (
        <div role="alert" style={{ fontSize: "0.74rem", color: "#FF5050", background: "rgba(255,80,80,0.06)", borderRadius: 8, padding: "8px 12px", wordBreak: "break-word" }}>
          {errorMsg}
        </div>
      )}

      {/* Pending tx link */}
      {withdrawHash && !withdrawConfirmed && (
        <a href={`https://sepolia.uniscan.xyz/tx/${withdrawHash}`} target="_blank" rel="noopener noreferrer"
          style={{ fontSize: "0.73rem", color: "#00AAFF", textDecoration: "none" }}
          aria-label="View withdraw transaction on Uniscan (opens in new tab)">
          Withdraw tx pending — view on Uniscan ↗
        </a>
      )}

      {/* Success message */}
      {withdrawn && !errorMsg && (
        <div style={{ fontSize: "0.8rem", color: "#00C864", fontWeight: 600 }}>
          Withdrawn successfully ✓
        </div>
      )}

      {/* Withdraw button */}
      {!pos.closed && !withdrawn && (
        <button type="button" disabled={isPending} onClick={handleWithdraw} aria-busy={isPending}
          style={{
            background: "rgba(255,80,80,0.1)",
            border: "1px solid rgba(255,80,80,0.3)",
            borderRadius: 10, padding: "10px 16px",
            color: isPending ? "#884444" : "#FF8080",
            fontWeight: 700, fontSize: "0.85rem",
            cursor: isPending ? "not-allowed" : "pointer",
            transition: "all 0.2s",
          }}>
          {isPending ? "Withdrawing…" : "Withdraw Position"}
        </button>
      )}
    </div>
  );
}

/* ── Main component ──────────────────────────────────────── */
export function MyPositions({ refreshKey }: { refreshKey?: number }) {
  const { address } = useAccount();
  const [localKey, setLocalKey] = useState(0);

  const { data: positionIds, isLoading, isError, refetch } = useReadContract({
    address: CONTRACTS.HOOK,
    abi: StableStreamHookABI,
    functionName: "getOwnerPositions",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 20_000 },
  });

  /* Re-fetch when parent signals a new deposit */
  useEffect(() => {
    if (refreshKey !== undefined && refreshKey > 0) refetch();
  }, [refreshKey, refetch]);

  function handleRefresh() { setLocalKey((k) => k + 1); refetch(); }

  const ids = Array.isArray(positionIds) ? (positionIds as `0x${string}`[]) : [];

  return (
    <div style={{
      background: "linear-gradient(135deg, rgba(8,15,30,0.95), rgba(5,10,20,0.95))",
      border: "1px solid rgba(0,102,255,0.2)",
      borderRadius: 20, padding: "32px 28px",
      display: "flex", flexDirection: "column", gap: 24,
    }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 12 }}>
        <div>
          <h3 style={{ fontWeight: 800, fontSize: "1.15rem", marginBottom: 4 }}>My Positions</h3>
          <p style={{ color: "#4A6FA5", fontSize: "0.82rem" }}>
            {isLoading
              ? "Loading…"
              : ids.length === 0
              ? "No positions yet — deposit USDC to get started."
              : `${ids.length} position${ids.length === 1 ? "" : "s"} found`}
          </p>
        </div>
        <button type="button" onClick={handleRefresh} disabled={isLoading}
          style={{
            background: "rgba(0,102,255,0.08)", border: "1px solid rgba(0,102,255,0.25)",
            borderRadius: 10, padding: "8px 14px", color: "#00AAFF",
            fontWeight: 600, fontSize: "0.78rem",
            cursor: isLoading ? "not-allowed" : "pointer", flexShrink: 0,
          }}>
          Refresh
        </button>
      </div>

      {/* Error */}
      {isError && (
        <div role="alert" style={{ background: "rgba(255,80,80,0.06)", border: "1px solid rgba(255,80,80,0.2)", borderRadius: 12, padding: "14px 18px", color: "#FF8080", fontSize: "0.82rem" }}>
          Failed to load positions. Check your connection or click Refresh.
        </div>
      )}

      {/* Loading skeletons */}
      {isLoading && (
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <CardSkeleton />
          <CardSkeleton />
        </div>
      )}

      {/* Positions */}
      {!isLoading && ids.length > 0 && (
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          {ids.map((id) => (
            <PositionCard
              key={`${id}-${localKey}-${refreshKey ?? 0}`}
              positionId={id}
              onWithdrawn={handleRefresh}
            />
          ))}
        </div>
      )}

      {/* Empty state */}
      {!isLoading && !isError && ids.length === 0 && (
        <div style={{ textAlign: "center", padding: "32px 0", color: "#4A6FA5" }}>
          <div style={{ fontSize: "2.5rem", marginBottom: 12, opacity: 0.4 }}>◎</div>
          <p style={{ fontSize: "0.875rem" }}>Your positions will appear here after your first deposit.</p>
        </div>
      )}
    </div>
  );
}
