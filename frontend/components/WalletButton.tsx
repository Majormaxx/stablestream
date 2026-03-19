"use client";

import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain } from "wagmi";
import { UNICHAIN_SEPOLIA } from "@/lib/contracts";

function truncate(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

const btnBase: React.CSSProperties = {
  borderRadius: "10px",
  padding: "10px 22px",
  fontWeight: 700,
  fontSize: "0.875rem",
  color: "#fff",
  cursor: "pointer",
  border: "none",
  transition: "opacity 0.2s, transform 0.1s",
  outline: "none",
};

export function WalletButton() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending: isConnecting } = useConnect();
  const { disconnect, isPending: isDisconnecting } = useDisconnect();
  const chainId = useChainId();
  const { switchChain, isPending: isSwitching } = useSwitchChain();

  const wrongNetwork = isConnected && chainId !== UNICHAIN_SEPOLIA.id;

  // Safely get first available connector
  const connector = connectors[0];

  if (!isConnected) {
    return (
      <button
        type="button"
        onClick={() => connector && connect({ connector })}
        disabled={isConnecting || !connector}
        aria-label="Connect your wallet to StableStream"
        aria-busy={isConnecting}
        style={{
          ...btnBase,
          background: isConnecting
            ? "linear-gradient(135deg, #0044BB, #0088CC)"
            : "linear-gradient(135deg, #0066FF, #00AAFF)",
          boxShadow: "0 4px 20px rgba(0,102,255,0.3)",
          opacity: isConnecting || !connector ? 0.7 : 1,
          cursor: isConnecting || !connector ? "not-allowed" : "pointer",
        }}
        onFocus={(e) => (e.currentTarget.style.boxShadow = "0 0 0 3px rgba(0,170,255,0.4), 0 4px 20px rgba(0,102,255,0.3)")}
        onBlur={(e) => (e.currentTarget.style.boxShadow = "0 4px 20px rgba(0,102,255,0.3)")}
        onMouseOver={(e) => { if (!isConnecting) e.currentTarget.style.opacity = "0.85"; }}
        onMouseOut={(e) => (e.currentTarget.style.opacity = isConnecting ? "0.7" : "1")}
      >
        {isConnecting ? "Connecting…" : "Connect Wallet"}
      </button>
    );
  }

  if (wrongNetwork) {
    return (
      <button
        type="button"
        onClick={() => switchChain({ chainId: UNICHAIN_SEPOLIA.id })}
        disabled={isSwitching}
        aria-label="Switch network to Unichain Sepolia"
        aria-busy={isSwitching}
        style={{
          ...btnBase,
          background: "linear-gradient(135deg, #FF6B00, #FFB800)",
          opacity: isSwitching ? 0.7 : 1,
          cursor: isSwitching ? "not-allowed" : "pointer",
        }}
        onFocus={(e) => (e.currentTarget.style.boxShadow = "0 0 0 3px rgba(255,184,0,0.4)")}
        onBlur={(e) => (e.currentTarget.style.boxShadow = "none")}
      >
        {isSwitching ? "Switching…" : "Switch to Unichain Sepolia"}
      </button>
    );
  }

  return (
    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
      <div
        role="status"
        aria-label={`Connected: ${address ?? ""} on Unichain Sepolia`}
        style={{
          display: "flex", alignItems: "center", gap: 8,
          border: "1px solid rgba(0,170,255,0.3)",
          borderRadius: "10px", padding: "8px 14px",
          background: "rgba(0,102,255,0.08)",
          fontSize: "0.8rem",
        }}
      >
        <span
          aria-hidden="true"
          style={{ width: 7, height: 7, borderRadius: "50%", background: "#00D4FF", display: "inline-block" }}
        />
        <span style={{ color: "#F0F4FF", fontWeight: 600 }}>
          {address ? truncate(address) : ""}
        </span>
        <span style={{ color: "#4A6FA5" }}>· Unichain Sepolia</span>
      </div>
      <button
        type="button"
        onClick={() => disconnect()}
        disabled={isDisconnecting}
        aria-label="Disconnect wallet"
        aria-busy={isDisconnecting}
        style={{
          background: "transparent",
          border: "1px solid rgba(255,100,100,0.3)",
          borderRadius: "8px", padding: "8px 12px",
          color: "#FF6B6B", fontSize: "0.75rem",
          cursor: isDisconnecting ? "not-allowed" : "pointer",
          fontWeight: 600,
          opacity: isDisconnecting ? 0.6 : 1,
          outline: "none",
          transition: "box-shadow 0.15s",
        }}
        onFocus={(e) => (e.currentTarget.style.boxShadow = "0 0 0 3px rgba(255,107,107,0.3)")}
        onBlur={(e) => (e.currentTarget.style.boxShadow = "none")}
      >
        {isDisconnecting ? "Disconnecting…" : "Disconnect"}
      </button>
    </div>
  );
}
