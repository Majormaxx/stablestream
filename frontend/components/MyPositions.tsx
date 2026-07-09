"use client";

import { useState, useEffect } from "react";
import {
  useAccount,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { formatUnits, type Abi } from "viem";
import { CONTRACTS, StableStreamHookABI } from "@/lib/contracts";

const HOOK_ABI = StableStreamHookABI as Abi;
import { USDC_DECIMALS } from "@/lib/poolKey";

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

const PAGE_SIZE = 20;

function positionStatus(pos: TrackedPosition): { label: string; color: string } {
  if (pos.closed) return { label: "Closed", color: "#FF5050" };
  if (pos.activeYieldSource !== ZERO_ADDR && pos.yieldDeposited > 0n)
    return { label: "Earning Yield", color: "#FFB800" };
  return { label: "In Pool", color: "#00C864" };
}

function truncate(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

function CardSkeleton() {
  return (
    <div aria-busy="true" aria-label="Loading position"
      className="h-[180px] rounded-[14px] bg-gradient-to-r from-brand-500/6 via-brand-400/10 to-brand-500/6 bg-[length:200%_100%] animate-[shimmer_1.5s_infinite]"
    />
  );
}

function PositionCard({
  positionId,
  pos,
  isLoading,
  onWithdrawn,
}: {
  positionId: `0x${string}`;
  pos: TrackedPosition | undefined;
  isLoading: boolean;
  onWithdrawn: () => void;
}) {
  const [withdrawing, setWithdrawing]   = useState(false);
  const [withdrawn, setWithdrawn]       = useState(false);
  const [errorMsg, setErrorMsg]         = useState("");

  const { writeContract: writeWithdraw, isPending: withdrawPending, data: withdrawHash } =
    useWriteContract();

  const { isSuccess: withdrawConfirmed } = useWaitForTransactionReceipt({ hash: withdrawHash });

  useEffect(() => {
    if (withdrawConfirmed && withdrawing) {
      setWithdrawn(true);
      setWithdrawing(false);
      onWithdrawn();
    }
  }, [withdrawConfirmed, withdrawing, onWithdrawn]);

  function handleWithdraw() {
    setErrorMsg("");
    setWithdrawing(true);
    writeWithdraw(
      { address: CONTRACTS.HOOK, abi: HOOK_ABI, functionName: "withdraw", args: [positionId] },
      {
        onError: (e) => {
          console.error("withdraw error:", e);
          setErrorMsg("Withdrawal failed. Please try again or check your wallet.");
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
    <div className="bg-bg-card/85 border border-brand-500/18 rounded-[14px] p-5 flex flex-col gap-[14px]">
      <div className="flex justify-between items-start">
        <div>
          <div className="font-mono text-[0.72rem] text-text-muted mb-1">
            {truncate(positionId)}
          </div>
          <div className="inline-flex items-center gap-[6px]">
            <span className="w-[7px] h-[7px] rounded-full inline-block" style={{ background: status.color }} />
            <span className="font-bold text-[0.85rem]" style={{ color: status.color }}>{status.label}</span>
          </div>
        </div>
        <div className="text-right">
          <div className="text-[0.72rem] text-text-muted mb-0.5">Ticks</div>
          <div className="font-bold text-[0.9rem] font-mono text-text-primary">
            {pos.tickLower} → {pos.tickUpper}
          </div>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-2">
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
          <div key={m.label} className="bg-brand-500/5 rounded-[10px] p-[10px]">
            <div className="text-[0.65rem] text-text-muted mb-1 tracking-[0.5px]">{m.label}</div>
            <div className="font-extrabold text-[0.82rem] font-mono break-all" style={{ color: m.color }}>
              {m.value}
            </div>
          </div>
        ))}
      </div>

      {pos.activeYieldSource !== ZERO_ADDR && (
        <div className="text-[0.74rem] text-text-muted">
          Routing to:{" "}
          <a href={`https://sepolia.uniscan.xyz/address/${pos.activeYieldSource}`}
            target="_blank" rel="noopener noreferrer"
            className="text-brand-400 no-underline font-mono"
            aria-label="View yield source on Uniscan (opens in new tab)">
            {truncate(pos.activeYieldSource)} ↗
          </a>
        </div>
      )}

      {errorMsg && (
        <div role="alert" className="text-[0.74rem] text-error-500 bg-error-500/6 rounded-[8px] px-3 py-2 break-words">
          {errorMsg}
        </div>
      )}

      {withdrawHash && !withdrawConfirmed && (
        <a href={`https://sepolia.uniscan.xyz/tx/${withdrawHash}`} target="_blank" rel="noopener noreferrer"
          className="text-[0.73rem] text-brand-400 no-underline"
          aria-label="View withdraw transaction on Uniscan (opens in new tab)">
          Withdraw tx pending — view on Uniscan ↗
        </a>
      )}

      {withdrawn && !errorMsg && (
        <div className="text-[0.8rem] text-green-400 font-semibold">
          Withdrawn successfully ✓
        </div>
      )}

      {!pos.closed && !withdrawn && (
        <button type="button" disabled={isPending} onClick={handleWithdraw} aria-busy={isPending}
          className="rounded-[10px] px-4 py-[10px] font-bold text-[0.85rem] transition-all duration-200"
          style={{
            background: "rgba(255,80,80,0.1)",
            border: "1px solid rgba(255,80,80,0.3)",
            color: isPending ? "#884444" : "#FF8080",
            cursor: isPending ? "not-allowed" : "pointer",
          }}>
          {isPending ? "Withdrawing…" : "Withdraw Position"}
        </button>
      )}
    </div>
  );
}

export function MyPositions({ refreshKey }: { refreshKey?: number }) {
  const { address } = useAccount();
  const [localKey, setLocalKey] = useState(0);
  const [page, setPage] = useState(0);

  const { data: positionIds, isLoading, isError, refetch } = useReadContract({
    address: CONTRACTS.HOOK,
    abi: HOOK_ABI,
    functionName: "getOwnerPositions",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 20_000, refetchIntervalInBackground: false },
  });

  useEffect(() => {
    if (refreshKey !== undefined && refreshKey > 0) refetch();
  }, [refreshKey, refetch]);

  function handleRefresh() { setLocalKey((k) => k + 1); refetch(); }

  const ids = Array.isArray(positionIds) ? (positionIds as `0x${string}`[]) : [];
  const totalPages = Math.max(1, Math.ceil(ids.length / PAGE_SIZE));
  const pagedIds = ids.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE);

  const { data: positionsData, isLoading: posLoading } = useReadContracts({
    contracts: pagedIds.map((id) => ({
      address: CONTRACTS.HOOK as `0x${string}`,
      abi: HOOK_ABI,
      functionName: "getPosition" as const,
      args: [id] as const,
    })),
    query: {
      enabled: pagedIds.length > 0,
      refetchInterval: 20_000,
      refetchIntervalInBackground: false,
    },
  });

  return (
    <div className="bg-gradient-to-br from-bg-card/95 to-bg-deep/95 border border-brand-500/20 rounded-[20px] p-[32px_28px] flex flex-col gap-6">
      <div className="flex justify-between items-start gap-3">
        <div>
          <h3 className="font-extrabold text-[1.15rem] mb-1">My Positions</h3>
          <p className="text-text-muted text-[0.82rem]">
            {isLoading
              ? "Loading…"
              : ids.length === 0
              ? "No positions yet — deposit USDC to get started."
              : `${ids.length} position${ids.length === 1 ? "" : "s"} found`}
          </p>
        </div>
        <button type="button" onClick={handleRefresh} disabled={isLoading}
          className="rounded-[10px] px-[14px] py-2 font-semibold text-[0.78rem] shrink-0"
          style={{
            background: "rgba(0,102,255,0.08)",
            border: "1px solid rgba(0,102,255,0.25)",
            color: "#00AAFF",
            cursor: isLoading ? "not-allowed" : "pointer",
          }}>
          Refresh
        </button>
      </div>

      {isError && (
        <div role="alert" className="bg-error-500/6 border border-error-500/20 rounded-[12px] px-[18px] py-[14px] text-[#FF8080] text-[0.82rem]">
          Failed to load positions. Check your connection or click Refresh.
        </div>
      )}

      {isLoading && (
        <div className="flex flex-col gap-3">
          <CardSkeleton />
          <CardSkeleton />
        </div>
      )}

      {!isLoading && pagedIds.length > 0 && (
        <div className="flex flex-col gap-3">
          {pagedIds.map((id, i) => (
            <PositionCard
              key={`${id}-${localKey}-${refreshKey ?? 0}`}
              positionId={id}
              pos={positionsData?.[i]?.result as TrackedPosition | undefined}
              isLoading={posLoading}
              onWithdrawn={handleRefresh}
            />
          ))}
          {totalPages > 1 && (
            <div className="flex justify-center gap-[10px] pt-1">
              <button type="button" onClick={() => setPage((p) => Math.max(0, p - 1))} disabled={page === 0}
                className="rounded-[8px] px-[14px] py-[6px] font-semibold text-[0.78rem]"
                style={{ background: "rgba(0,102,255,0.08)", border: "1px solid rgba(0,102,255,0.25)", color: "#00AAFF", cursor: page === 0 ? "not-allowed" : "pointer" }}>
                ← Prev
              </button>
              <span className="text-text-muted text-[0.8rem] self-center">
                {page + 1} / {totalPages}
              </span>
              <button type="button" onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))} disabled={page >= totalPages - 1}
                className="rounded-[8px] px-[14px] py-[6px] font-semibold text-[0.78rem]"
                style={{ background: "rgba(0,102,255,0.08)", border: "1px solid rgba(0,102,255,0.25)", color: "#00AAFF", cursor: page >= totalPages - 1 ? "not-allowed" : "pointer" }}>
                Next →
              </button>
            </div>
          )}
        </div>
      )}

      {!isLoading && !isError && ids.length === 0 && (
        <div className="text-center py-8 text-text-muted">
          <div className="text-[2.5rem] mb-3 opacity-40">◎</div>
          <p className="text-[0.875rem]">Your positions will appear here after your first deposit.</p>
        </div>
      )}
    </div>
  );
}
