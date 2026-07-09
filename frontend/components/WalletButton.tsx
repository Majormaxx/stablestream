"use client";

import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain } from "wagmi";
import { UNICHAIN_SEPOLIA } from "@/lib/contracts";

function truncate(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function WalletButton() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending: isConnecting } = useConnect();
  const { disconnect, isPending: isDisconnecting } = useDisconnect();
  const chainId = useChainId();
  const { switchChain, isPending: isSwitching } = useSwitchChain();

  const wrongNetwork = isConnected && chainId !== UNICHAIN_SEPOLIA.id;

  const connector = connectors[0];

  if (!isConnected) {
    return (
      <button
        type="button"
        onClick={() => connector && connect({ connector })}
        disabled={isConnecting || !connector}
        aria-label="Connect your wallet to StableStream"
        aria-busy={isConnecting}
        className="rounded-[10px] px-[22px] py-[10px] font-bold text-[0.875rem] text-white border-none transition-all duration-200 focus:shadow-[0_0_0_3px_rgba(0,170,255,0.4),0_4px_20px_rgba(0,102,255,0.3)]"
        style={{
          background: isConnecting
            ? "linear-gradient(135deg, #0044BB, #0088CC)"
            : "linear-gradient(135deg, #0066FF, #00AAFF)",
          boxShadow: "0 4px 20px rgba(0,102,255,0.3)",
          opacity: isConnecting || !connector ? 0.7 : 1,
          cursor: isConnecting || !connector ? "not-allowed" : "pointer",
        }}
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
        className="rounded-[10px] px-[22px] py-[10px] font-bold text-[0.875rem] text-white border-none transition-all duration-200 focus:shadow-[0_0_0_3px_rgba(255,184,0,0.4)]"
        style={{
          background: "linear-gradient(135deg, #FF6B00, #FFB800)",
          opacity: isSwitching ? 0.7 : 1,
          cursor: isSwitching ? "not-allowed" : "pointer",
        }}
      >
        {isSwitching ? "Switching…" : "Switch to Unichain Sepolia"}
      </button>
    );
  }

  return (
    <div className="flex items-center gap-[10px]">
      <div
        role="status"
        aria-label={`Connected: ${address ?? ""} on Unichain Sepolia`}
        className="flex items-center gap-2 rounded-[10px] px-[14px] py-2 bg-brand-500/8 text-[0.8rem]"
        style={{ border: "1px solid rgba(0,170,255,0.3)" }}
      >
        <span aria-hidden="true" className="w-[7px] h-[7px] rounded-full bg-cyan-400 inline-block" />
        <span className="text-text-primary font-semibold">
          {address ? truncate(address) : ""}
        </span>
        <span className="text-text-muted">· Unichain Sepolia</span>
      </div>
      <button
        type="button"
        onClick={() => disconnect()}
        disabled={isDisconnecting}
        aria-label="Disconnect wallet"
        aria-busy={isDisconnecting}
        className="rounded-[8px] px-3 py-2 text-[0.75rem] font-semibold border-none transition-all duration-200 focus:shadow-[0_0_0_3px_rgba(255,107,107,0.3)]"
        style={{
          background: "transparent",
          border: "1px solid rgba(255,100,100,0.3)",
          color: "#FF6B6B",
          cursor: isDisconnecting ? "not-allowed" : "pointer",
          opacity: isDisconnecting ? 0.6 : 1,
        }}
      >
        {isDisconnecting ? "Disconnecting…" : "Disconnect"}
      </button>
    </div>
  );
}
