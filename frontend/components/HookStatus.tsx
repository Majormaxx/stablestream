"use client";

import { useReadContracts } from "wagmi";
import { CONTRACTS, StableStreamHookABI, YieldRouterABI } from "@/lib/contracts";

function RowSkeleton() {
  return (
    <div style={{
      display: "flex", justifyContent: "space-between", alignItems: "center",
      padding: "12px 0", borderBottom: "1px solid rgba(0,102,255,0.1)",
    }}>
      <span style={{
        display: "inline-block", width: "6rem", height: "0.9rem", borderRadius: 4,
        backgroundImage: "linear-gradient(90deg, rgba(0,102,255,0.12) 25%, rgba(0,170,255,0.18) 50%, rgba(0,102,255,0.12) 75%)",
        backgroundSize: "200% 100%",
        animation: "shimmer 1.5s infinite",
      }} aria-hidden="true" />
      <span style={{
        display: "inline-block", width: "10rem", height: "0.9rem", borderRadius: 4,
        backgroundImage: "linear-gradient(90deg, rgba(0,102,255,0.12) 25%, rgba(0,170,255,0.18) 50%, rgba(0,102,255,0.12) 75%)",
        backgroundSize: "200% 100%",
        animation: "shimmer 1.5s infinite",
      }} aria-hidden="true" />
    </div>
  );
}

function Row({ label, value, mono, isError }: {
  label: string; value: string; mono?: boolean; isError?: boolean;
}) {
  return (
    <div style={{
      display: "flex", justifyContent: "space-between", alignItems: "center",
      padding: "12px 0", borderBottom: "1px solid rgba(0,102,255,0.1)",
      flexWrap: "wrap", gap: 8,
    }}>
      <span style={{ color: "#4A6FA5", fontSize: "0.85rem" }}>{label}</span>
      <span style={{
        fontFamily: mono ? "monospace" : "inherit",
        fontSize: "0.82rem",
        color: isError ? "#FF6B6B" : "#F0F4FF",
        fontWeight: 600,
      }}>
        {value}
      </span>
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
      // Hook reads
      { address: CONTRACTS.HOOK, abi: StableStreamHookABI, functionName: "reactiveContract" },
      { address: CONTRACTS.HOOK, abi: StableStreamHookABI, functionName: "nft" },
      { address: CONTRACTS.HOOK, abi: StableStreamHookABI, functionName: "owner" },
      // YieldRouter reads
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
    <section aria-labelledby="hook-status-heading" style={{ padding: "64px 24px" }}>
      <div style={{ maxWidth: 900, margin: "0 auto" }}>
        <p style={{ color: "#00AAFF", fontWeight: 600, fontSize: "0.75rem", letterSpacing: "2px", textAlign: "center", marginBottom: 8 }}>
          LIVE ON-CHAIN STATE · REFRESHES EVERY 30s
        </p>
        <h2
          id="hook-status-heading"
          style={{ textAlign: "center", fontWeight: 900, fontSize: "clamp(1.6rem,3vw,2.4rem)", letterSpacing: "-1px", marginBottom: 32 }}
        >
          Hook & Router Status
        </h2>

        {isError && (
          <div role="alert" style={{
            border: "1px solid rgba(255,107,107,0.3)",
            background: "rgba(255,107,107,0.06)",
            borderRadius: 12, padding: "14px 20px",
            color: "#FF6B6B", fontSize: "0.85rem", textAlign: "center", marginBottom: 24,
          }}>
            Failed to load on-chain data. Check your connection or try refreshing.
          </div>
        )}

        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(340px, 1fr))", gap: 20 }}>
          {/* Hook card */}
          <div
            role="region"
            aria-label="StableStreamHook contract status"
            style={{ border: "1px solid rgba(0,102,255,0.18)", borderRadius: 16, padding: "24px 28px", background: "rgba(8,15,30,0.8)" }}
          >
            <div style={{ fontWeight: 700, fontSize: "0.9rem", color: "#00AAFF", marginBottom: 16, letterSpacing: "0.5px" }}>
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
                {/* RSC detail block */}
                <div style={{
                  padding: "10px 12px",
                  background: rscLive ? "rgba(0,200,100,0.05)" : "rgba(255,80,80,0.05)",
                  border: `1px solid ${rscLive ? "rgba(0,200,100,0.2)" : "rgba(255,80,80,0.15)"}`,
                  borderRadius: 10,
                  marginTop: 4,
                  display: "flex",
                  flexDirection: "column",
                  gap: 6,
                }}>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                    <span style={{ fontSize: "0.75rem", color: rscLive ? "#00C864" : "#FF8080", fontWeight: 700 }}>
                      {rscLive ? "● Connected" : "○ Not set"}
                    </span>
                    {rscLive && (
                      <span style={{
                        fontSize: "0.68rem", fontWeight: 700, letterSpacing: "0.5px",
                        background: "rgba(0,170,255,0.12)", border: "1px solid rgba(0,170,255,0.25)",
                        borderRadius: 6, padding: "2px 8px", color: "#00AAFF",
                      }}>
                        Lasna · Chain 5318007
                      </span>
                    )}
                  </div>
                  {rscLive && (
                    <>
                      <div style={{ display: "flex", justifyContent: "space-between", fontSize: "0.72rem", color: "#4A6FA5" }}>
                        <span>Monitoring chain</span>
                        <span style={{ color: "#F0F4FF", fontWeight: 600 }}>Unichain Sepolia (1301)</span>
                      </div>
                      <div style={{ display: "flex", justifyContent: "space-between", fontSize: "0.72rem", color: "#4A6FA5" }}>
                        <span>Callback target</span>
                        <span style={{ color: "#F0F4FF", fontWeight: 600 }}>Unichain Sepolia (1301)</span>
                      </div>
                      <a
                        href={`${LASNA_EXPLORER}/address/${RSC_ADDR}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        style={{ fontSize: "0.72rem", color: "#00AAFF", marginTop: 2 }}
                        aria-label="View RSC on Lasna explorer (opens in new tab)"
                      >
                        View on Lasna explorer ↗
                      </a>
                    </>
                  )}
                </div>
              </>
            )}
          </div>

          {/* Router card */}
          <div
            role="region"
            aria-label="YieldRouter contract status"
            style={{ border: "1px solid rgba(0,102,255,0.18)", borderRadius: 16, padding: "24px 28px", background: "rgba(8,15,30,0.8)" }}
          >
            <div style={{ fontWeight: 700, fontSize: "0.9rem", color: "#00AAFF", marginBottom: 16, letterSpacing: "0.5px" }}>
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
          </div>
        </div>
      </div>
    </section>
  );
}
