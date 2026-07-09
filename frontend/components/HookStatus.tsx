"use client";

import { useReadContracts } from "wagmi";
import { CONTRACTS, StableStreamHookABI, YieldRouterABI } from "@/lib/contracts";
import { Card } from "@/components/ui/Card";
import { ErrorState } from "@/components/ui/ErrorState";
import { Skeleton } from "@/components/ui/Skeleton";

function Row({ label, value, mono, isError }: {
  label: string; value: string; mono?: boolean; isError?: boolean;
}) {
  return (
    <div className="flex justify-between items-center flex-wrap gap-2 py-3 border-b border-rail/40">
      <span className="text-slate text-[0.85rem]">{label}</span>
      <span className={`text-[0.82rem] font-semibold ${mono ? "font-mono" : ""} ${isError ? "text-error" : "text-paper"}`}>
        {value}
      </span>
    </div>
  );
}

function RowSkeleton() {
  return (
    <div className="flex justify-between items-center py-3 border-b border-rail/40">
      <Skeleton width="6rem" height="0.9rem" />
      <Skeleton width="10rem" height="0.9rem" />
    </div>
  );
}

function safeAddr(val: unknown): string {
  if (typeof val === "string" && val.startsWith("0x") && val.length === 42) {
    return `${val.slice(0, 8)}…${val.slice(-6)}`;
  }
  return "—";
}

export function HookStatus() {
  const { data, isLoading, isError } = useReadContracts({
    contracts: [
      { address: CONTRACTS.HOOK, abi: StableStreamHookABI, functionName: "reactiveContract" },
      { address: CONTRACTS.HOOK, abi: StableStreamHookABI, functionName: "nft" },
      { address: CONTRACTS.HOOK, abi: StableStreamHookABI, functionName: "owner" },
      { address: CONTRACTS.YIELD_ROUTER, abi: YieldRouterABI, functionName: "owner" },
      { address: CONTRACTS.YIELD_ROUTER, abi: YieldRouterABI, functionName: "sourceCount" },
      { address: CONTRACTS.YIELD_ROUTER, abi: YieldRouterABI, functionName: "authorizedCaller" },
    ],
    query: { refetchInterval: 30_000 },
  });

  const [rscR, nftR, hookOwnerR, routerOwnerR, sourceCountR, authCallerR] = data ?? [];

  const ZERO = "0x0000000000000000000000000000000000000000";

  const RSC_ADDR    = "0xa86591459C15d12F13AbaDf0d78Ec56F3e920a80";
  const LASNA_EXPLORER = "https://lasna.reactscan.net";

  const rscAddr  = typeof rscR?.result === "string" ? rscR.result : ZERO;
  const rscLive  = rscAddr !== ZERO && rscAddr.toLowerCase() === RSC_ADDR.toLowerCase();
  const rscLabel = rscLive ? safeAddr(RSC_ADDR) : "Not configured";

  const sourceCount = sourceCountR?.status === "success" ? String(sourceCountR.result) : "—";
  const authCaller  = authCallerR?.status === "success" ? safeAddr(authCallerR.result) : "—";

  return (
    <section aria-labelledby="hook-status-heading" className="px-6 py-16">
      <div className="max-w-[900px] mx-auto">
        <p className="text-signal font-mono text-[0.7rem] tracking-[2px] text-center mb-2">
          LIVE ON-CHAIN STATE · REFRESHES EVERY 30s
        </p>
        <h2
          id="hook-status-heading"
          className="text-center font-black text-[clamp(1.6rem,3vw,2.4rem)] -tracking-[1px] mb-8 font-display"
        >
          Hook & Router Status
        </h2>

        {isError && (
          <div className="mb-6">
            <ErrorState message="Failed to load on-chain data. Check your connection or try refreshing." />
          </div>
        )}

        <div className="grid grid-cols-[repeat(auto-fit,minmax(340px,1fr))] gap-5">
          {/* Hook card */}
          <Card role="region" aria-label="StableStreamHook contract status">
            <div className="font-bold text-[0.9rem] text-signal mb-4 tracking-[0.5px]">
              StableStreamHook
            </div>
            {isLoading ? (
              <>{[0,1,2,3,4].map((i) => <RowSkeleton key={i} />)}</>
            ) : (
              <>
                <Row label="Address"          value={`${CONTRACTS.HOOK.slice(0,8)}…${CONTRACTS.HOOK.slice(-6)}`} mono />
                <Row label="Owner"            value={safeAddr(hookOwnerR?.result)} mono isError={hookOwnerR?.status === "failure"} />
                <Row label="NFT Contract"     value={safeAddr(nftR?.result)}       mono isError={nftR?.status === "failure"} />
                <Row label="Reactive (RSC)" value={rscLabel} mono={rscLive} isError={!rscLive} />
                <div
                  className="mt-1 p-[10px_12px] rounded-[var(--radius-control)] flex flex-col gap-[6px]"
                  style={{
                    background: rscLive ? "rgba(62,201,176,0.06)" : "rgba(217,99,75,0.06)",
                    border: `1px solid ${rscLive ? "rgba(62,201,176,0.25)" : "rgba(217,99,75,0.2)"}`,
                  }}
                >
                  <div className="flex justify-between items-center">
                    <span className={`text-[0.75rem] font-bold ${rscLive ? "text-current" : "text-error"}`}>
                      {rscLive ? "● Connected" : "○ Not set"}
                    </span>
                    {rscLive && (
                      <span className="text-[0.68rem] font-bold tracking-[0.5px] bg-signal/10 border border-signal/20 rounded-[var(--radius-control)] px-2 py-[2px] text-signal">
                        Lasna · Chain 5318007
                      </span>
                    )}
                  </div>
                  {rscLive && (
                    <>
                      <div className="flex justify-between text-[0.72rem] text-slate">
                        <span>Monitoring chain</span>
                        <span className="text-paper font-semibold">Unichain Sepolia (1301)</span>
                      </div>
                      <div className="flex justify-between text-[0.72rem] text-slate">
                        <span>Callback target</span>
                        <span className="text-paper font-semibold">Unichain Sepolia (1301)</span>
                      </div>
                      <a
                        href={`${LASNA_EXPLORER}/address/${RSC_ADDR}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-[0.72rem] text-signal mt-0.5"
                        aria-label="View RSC on Lasna explorer (opens in new tab)"
                      >
                        View on Lasna explorer ↗
                      </a>
                    </>
                  )}
                </div>
              </>
            )}
          </Card>

          {/* Router card */}
          <Card role="region" aria-label="YieldRouter contract status">
            <div className="font-bold text-[0.9rem] text-signal mb-4 tracking-[0.5px]">
              YieldRouter
            </div>
            {isLoading ? (
              <>{[0,1,2,3,4].map((i) => <RowSkeleton key={i} />)}</>
            ) : (
              <>
                <Row label="Address"         value={`${CONTRACTS.YIELD_ROUTER.slice(0,8)}…${CONTRACTS.YIELD_ROUTER.slice(-6)}`} mono />
                <Row label="Owner"           value={safeAddr(routerOwnerR?.result)} mono isError={routerOwnerR?.status === "failure"} />
                <Row label="Yield Sources"   value={sourceCount}                    isError={sourceCountR?.status === "failure"} />
                <Row label="Authorized Hook" value={authCaller}                     mono isError={authCallerR?.status === "failure"} />
                <Row label="Active Adapter"  value="Compound V3" />
              </>
            )}
          </Card>
        </div>
      </div>
    </section>
  );
}
