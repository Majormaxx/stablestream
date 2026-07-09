"use client";

import { CONTRACTS, POOL_ID } from "@/lib/contracts";
import { Card } from "@/components/ui/Card";

const contracts = [
  { name: "YieldRouter",        address: CONTRACTS.YIELD_ROUTER,     desc: "Finds and deploys capital to the best yield source" },
  { name: "CompoundV3Adapter",  address: CONTRACTS.COMPOUND_ADAPTER, desc: "Connection to Compound for seamless yield access" },
  { name: "StableStreamHook",   address: CONTRACTS.HOOK,             desc: "Monitors, routes, and recalls automatically" },
  { name: "StableStreamNFT",    address: CONTRACTS.NFT,              desc: "Position receipt on-chain — track earnings and prove ownership" },
];

export function ContractExplorer() {
  return (
    <section
      id="contracts"
      aria-labelledby="contracts-heading"
      className="px-6 py-16 bg-channel/30 border-t border-rail/60"
    >
      <div className="max-w-[900px] mx-auto">
        <p className="text-signal font-mono text-[0.7rem] tracking-[2px] text-center mb-2">
          VERIFIED ON UNISCAN
        </p>
        <h2
          id="contracts-heading"
          className="text-center font-black text-[clamp(1.6rem,3vw,2.4rem)] -tracking-[1px] mb-8 font-display"
        >
          Deployed Contracts
        </h2>

        <ul className="flex flex-col gap-3 list-none p-0 m-0">
          {contracts.map((c) => (
            <li key={c.name} className="card-hover rounded-[var(--radius-panel)]"
              style={{ border: "1px solid var(--color-rail, #1E2621)", background: "rgba(20,26,23,0.6)" }}
            >
              <div className="flex items-center justify-between flex-wrap gap-3 p-[18px_24px]">
                <div>
                  <div className="font-bold text-[0.95rem] text-paper">{c.name}</div>
                  <div className="font-mono text-[0.78rem] text-signal mt-0.5" title={c.address}>
                    {c.address}
                  </div>
                  <div className="text-[0.72rem] text-slate mt-[3px]">{c.desc}</div>
                </div>
                <a
                  href={`https://sepolia.uniscan.xyz/address/${c.address}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  aria-label={`View ${c.name} on Uniscan (opens in new tab)`}
                  className="text-signal font-semibold text-[0.78rem] border border-signal/30 rounded-[var(--radius-control)] px-4 py-[7px] whitespace-nowrap no-underline transition-all duration-200 hover:bg-signal/10"
                >
                  View on Uniscan ↗
                </a>
              </div>
            </li>
          ))}
        </ul>

        <div
          role="region"
          aria-label="ETH/USDC pool information"
          className="mt-6 rounded-[var(--radius-panel)] p-[18px_24px]"
          style={{ border: "1px solid var(--color-rail, #1E2621)", background: "rgba(62,201,176,0.04)" }}
        >
          <div className="flex items-center justify-between flex-wrap gap-3">
            <div>
              <div className="font-bold text-[0.9rem] text-current">ETH / USDC Pool</div>
              <div className="font-mono text-[0.72rem] text-slate mt-1 break-all" title={POOL_ID}>
                Pool ID: {POOL_ID}
              </div>
              <div className="text-[0.72rem] text-slate mt-0.5">
                0.05% fee · tick spacing 10 · StableStreamHook attached
              </div>
            </div>
            <a
              href={`https://sepolia.uniscan.xyz/address/${CONTRACTS.HOOK}`}
              target="_blank"
              rel="noopener noreferrer"
              aria-label="View ETH/USDC pool on Uniscan (opens in new tab)"
              className="font-semibold text-[0.78rem] rounded-[var(--radius-control)] px-4 py-[7px] whitespace-nowrap no-underline transition-all duration-200 hover:bg-signal/10 text-signal"
              style={{ border: "1px solid rgba(232,163,61,0.3)" }}
            >
              View Pool ↗
            </a>
          </div>
        </div>
      </div>
    </section>
  );
}
