"use client";

import { CONTRACTS, POOL_ID } from "@/lib/contracts";

const contracts = [
  { name: "YieldRouter",        address: CONTRACTS.YIELD_ROUTER,     desc: "Finds and deploys capital to the best yield source" },
  { name: "CompoundV3Adapter",  address: CONTRACTS.COMPOUND_ADAPTER, desc: "Connection to Compound for seamless yield access" },
  { name: "StableStreamHook",   address: CONTRACTS.HOOK,             desc: "The heart of StableStream. Monitors, routes, and recalls automatically." },
  { name: "StableStreamNFT",    address: CONTRACTS.NFT,              desc: "Your position receipt on-chain. Track earnings and prove ownership." },
];

const linkStyle: React.CSSProperties = {
  color: "#00AAFF",
  fontWeight: 600,
  fontSize: "0.78rem",
  border: "1px solid rgba(0,170,255,0.3)",
  borderRadius: 8,
  padding: "7px 16px",
  whiteSpace: "nowrap",
  textDecoration: "none",
  transition: "background 0.2s, box-shadow 0.15s",
  outline: "none",
};

export function ContractExplorer() {
  return (
    <section
      id="contracts"
      aria-labelledby="contracts-heading"
      style={{ padding: "64px 24px", background: "rgba(8,15,30,0.5)", borderTop: "1px solid rgba(0,102,255,0.1)" }}
    >
      <div style={{ maxWidth: 900, margin: "0 auto" }}>
        <p style={{ color: "#00AAFF", fontWeight: 600, fontSize: "0.75rem", letterSpacing: "2px", textAlign: "center", marginBottom: 8 }}>
          VERIFIED ON UNISCAN
        </p>
        <h2
          id="contracts-heading"
          style={{ textAlign: "center", fontWeight: 900, fontSize: "clamp(1.6rem,3vw,2.4rem)", letterSpacing: "-1px", marginBottom: 32 }}
        >
          Deployed Contracts
        </h2>

        <ul style={{ display: "flex", flexDirection: "column", gap: 12, listStyle: "none", padding: 0, margin: 0 }}>
          {contracts.map((c) => (
            <li key={c.name} style={{
              display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 12,
              border: "1px solid rgba(0,102,255,0.18)",
              background: "rgba(5,10,20,0.7)",
              borderRadius: 14, padding: "18px 24px",
              transition: "border-color 0.2s, box-shadow 0.2s",
            }}
              onMouseOver={(e) => { e.currentTarget.style.borderColor = "rgba(0,170,255,0.4)"; e.currentTarget.style.boxShadow = "0 8px 32px rgba(0,102,255,0.1)"; }}
              onMouseOut={(e) => { e.currentTarget.style.borderColor = "rgba(0,102,255,0.18)"; e.currentTarget.style.boxShadow = "none"; }}
            >
              <div>
                <div style={{ fontWeight: 700, fontSize: "0.95rem", color: "#F0F4FF" }}>{c.name}</div>
                <div
                  style={{ fontFamily: "monospace", fontSize: "0.78rem", color: "#00AAFF", marginTop: 2 }}
                  title={c.address}
                >
                  {c.address}
                </div>
                <div style={{ fontSize: "0.72rem", color: "#4A6FA5", marginTop: 3 }}>{c.desc}</div>
              </div>
              <a
                href={`https://sepolia.uniscan.xyz/address/${c.address}`}
                target="_blank"
                rel="noopener noreferrer"
                aria-label={`View ${c.name} on Uniscan (opens in new tab)`}
                style={linkStyle}
                onMouseOver={(e) => { e.currentTarget.style.background = "rgba(0,102,255,0.12)"; }}
                onMouseOut={(e) => { e.currentTarget.style.background = "transparent"; }}
                onFocus={(e) => { e.currentTarget.style.boxShadow = "0 0 0 3px rgba(0,170,255,0.4)"; }}
                onBlur={(e) => { e.currentTarget.style.boxShadow = "none"; }}
              >
                View on Uniscan ↗
              </a>
            </li>
          ))}
        </ul>

        {/* Pool info */}
        <div
          role="region"
          aria-label="ETH/USDC pool information"
          style={{
            marginTop: 24,
            border: "1px solid rgba(255,184,0,0.2)",
            background: "rgba(255,184,0,0.04)",
            borderRadius: 14, padding: "18px 24px",
          }}
        >
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 12 }}>
            <div>
              <div style={{ fontWeight: 700, fontSize: "0.9rem", color: "#FFB800" }}>ETH / USDC Pool</div>
              <div
                style={{ fontFamily: "monospace", fontSize: "0.72rem", color: "#4A6FA5", marginTop: 4, wordBreak: "break-all" }}
                title={POOL_ID}
              >
                Pool ID: {POOL_ID}
              </div>
              <div style={{ fontSize: "0.72rem", color: "#4A6FA5", marginTop: 2 }}>
                0.05% fee · tick spacing 10 · StableStreamHook attached
              </div>
            </div>
            <a
              href={`https://sepolia.uniscan.xyz/address/${CONTRACTS.HOOK}`}
              target="_blank"
              rel="noopener noreferrer"
              aria-label="View ETH/USDC pool on Uniscan (opens in new tab)"
              style={{ ...linkStyle, color: "#FFB800", border: "1px solid rgba(255,184,0,0.3)" }}
              onFocus={(e) => { e.currentTarget.style.boxShadow = "0 0 0 3px rgba(255,184,0,0.3)"; }}
              onBlur={(e) => { e.currentTarget.style.boxShadow = "none"; }}
            >
              View Pool ↗
            </a>
          </div>
        </div>
      </div>
    </section>
  );
}
