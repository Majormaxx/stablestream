"use client";

import { useState, useEffect } from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits, formatUnits } from "viem";
import { CONTRACTS, StableStreamHookABI } from "@/lib/contracts";
import { ERC20_ABI } from "@/lib/erc20Abi";
import { POOL_KEY, TICK_RANGES, USDC_DECIMALS } from "@/lib/poolKey";

type Step = "idle" | "approving" | "approved" | "depositing" | "done" | "error";

/* ── "What are ticks?" collapsible explainer ─────────────── */
function TicksExplainer() {
  const [open, setOpen] = useState(false);
  return (
    <div style={{ position: "relative" }}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        aria-controls="ticks-explainer"
        style={{
          background: "rgba(0,170,255,0.08)",
          border: "1px solid rgba(0,170,255,0.25)",
          borderRadius: 8,
          padding: "4px 10px",
          color: "#00AAFF",
          fontSize: "0.72rem",
          fontWeight: 600,
          cursor: "pointer",
          display: "flex",
          alignItems: "center",
          gap: 4,
        }}
      >
        What are ticks? {open ? "▲" : "▼"}
      </button>

      {open && (
        <div
          id="ticks-explainer"
          role="region"
          aria-label="Explanation of ticks in Uniswap v4"
          style={{
            position: "absolute",
            right: 0,
            top: "calc(100% + 8px)",
            width: 300,
            background: "#080F1E",
            border: "1px solid rgba(0,170,255,0.25)",
            borderRadius: 12,
            padding: "16px 18px",
            zIndex: 50,
            boxShadow: "0 16px 48px rgba(0,0,0,0.6)",
          }}
        >
          <p style={{ fontSize: "0.78rem", color: "#F0F4FF", fontWeight: 700, marginBottom: 8 }}>
            What is a tick range?
          </p>
          <p style={{ fontSize: "0.75rem", color: "#4A6FA5", lineHeight: 1.6, marginBottom: 10 }}>
            In Uniswap, you choose a price range. Your liquidity earns swap fees when the price trades inside that range.
            When the price moves outside your range, you stop earning fees but your capital is still there—just idle.
          </p>
          <p style={{ fontSize: "0.75rem", color: "#4A6FA5", lineHeight: 1.6, marginBottom: 10 }}>
            <strong style={{ color: "#FFB800" }}> That&apos;s where StableStream steps in.</strong> While you wait for price to return, we put your capital to work earning yield from Compound or Aave. No lost opportunity.
          </p>
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            {[
              { label: "Tight ±10",    tip: "Higher fees when in range, frequent recall events" },
              { label: "Medium ±50",   tip: "Balanced. Good default for most users" },
              { label: "Wide ±200",    tip: "Less recall events, lower fee concentration" },
              { label: "Full range",   tip: "Always in range, behaves like a traditional LP" },
            ].map((row) => (
              <div key={row.label} style={{ display: "flex", gap: 8, alignItems: "flex-start" }}>
                <span style={{ fontWeight: 700, fontSize: "0.7rem", color: "#00AAFF", minWidth: 72, marginTop: 1 }}>
                  {row.label}
                </span>
                <span style={{ fontSize: "0.7rem", color: "#4A6FA5", lineHeight: 1.5 }}>{row.tip}</span>
              </div>
            ))}
          </div>
          <button
            type="button"
            onClick={() => setOpen(false)}
            style={{ marginTop: 12, fontSize: "0.7rem", color: "#4A6FA5", background: "none", border: "none", cursor: "pointer", padding: 0 }}
          >
            Close ✕
          </button>
        </div>
      )}
    </div>
  );
}

export function DepositForm({ onDeposited }: { onDeposited?: () => void }) {
  const { address } = useAccount();

  const [usdcInput, setUsdcInput]   = useState("");
  const [rangeIdx, setRangeIdx]     = useState(1); // Medium by default
  const [step, setStep]             = useState<Step>("idle");
  const [errorMsg, setErrorMsg]     = useState("");

  const range = TICK_RANGES[rangeIdx];

  /* ── USDC balance ──────────────────────────────────── */
  const { data: balance, refetch: refetchBalance } = useReadContract({
    address: CONTRACTS.USDC,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 15_000 },
  });

  /* ── USDC allowance ─────────────────────────────────── */
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: CONTRACTS.USDC,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: address ? [address, CONTRACTS.HOOK] : undefined,
    query: { enabled: !!address, refetchInterval: 10_000 },
  });

  /* ── Write: approve ─────────────────────────────────── */
  const { writeContract: writeApprove, isPending: approveIsPending, data: approveHash } =
    useWriteContract();

  const { isSuccess: approveConfirmed } = useWaitForTransactionReceipt({ hash: approveHash });

  /* ── Write: deposit ─────────────────────────────────── */
  const { writeContract: writeDeposit, isPending: depositIsPending, data: depositHash } =
    useWriteContract();

  const { isSuccess: depositConfirmed } = useWaitForTransactionReceipt({ hash: depositHash });

  /* ── Derived values ─────────────────────────────────── */
  const parsedAmount = (() => {
    if (!usdcInput) return 0n;
    try { return parseUnits(usdcInput, USDC_DECIMALS); }
    catch { return 0n; }
  })();

  const hasBalance   = balance !== undefined && parsedAmount > 0n && (balance as bigint) >= parsedAmount;
  const hasAllowance = allowance !== undefined && parsedAmount > 0n && (allowance as bigint) >= parsedAmount;
  const balanceFmt   = balance !== undefined ? formatUnits(balance as bigint, USDC_DECIMALS) : "—";

  // Show approve button when: allowance insufficient AND step hasn't already moved past approval
  const needsApprove = !hasAllowance && step !== "approved" && step !== "depositing" && step !== "done";

  /* ── React to approve confirmation ─────────────────── */
  useEffect(() => {
    if (approveConfirmed && step === "approving") {
      refetchAllowance();
      setStep("approved");
    }
  }, [approveConfirmed, step, refetchAllowance]);

  /* ── React to deposit confirmation ─────────────────── */
  useEffect(() => {
    if (depositConfirmed && step === "depositing") {
      refetchBalance();
      refetchAllowance();
      setStep("done");
      setUsdcInput("");
      onDeposited?.();
    }
  }, [depositConfirmed, step, refetchBalance, refetchAllowance, onDeposited]);

  /* ── Handlers ───────────────────────────────────────── */
  function handleApprove() {
    if (!parsedAmount) return;
    setErrorMsg("");
    setStep("approving");
    writeApprove(
      { address: CONTRACTS.USDC, abi: ERC20_ABI, functionName: "approve", args: [CONTRACTS.HOOK, parsedAmount] },
      { onError: (e) => { setErrorMsg(e.message.split("\n")[0]); setStep("error"); } }
    );
  }

  function handleDeposit() {
    if (!parsedAmount) return;
    setErrorMsg("");
    setStep("depositing");
    writeDeposit(
      {
        address: CONTRACTS.HOOK,
        abi: StableStreamHookABI,
        functionName: "deposit",
        args: [POOL_KEY, range.tickLower, range.tickUpper, parsedAmount],
      },
      { onError: (e) => { setErrorMsg(e.message.split("\n")[0]); setStep("error"); } }
    );
  }

  const isLoading = approveIsPending || depositIsPending || step === "approving" || step === "depositing";

  function resetForm() { setStep("idle"); setErrorMsg(""); setUsdcInput(""); }

  /* ── Button state ───────────────────────────────────── */
  const canAct = parsedAmount > 0n && hasBalance;

  const btnStyle = (active: boolean): React.CSSProperties => ({
    width: "100%",
    background: active ? "linear-gradient(135deg, #0066FF, #00D4FF)" : "rgba(0,102,255,0.12)",
    border: "none",
    borderRadius: 12,
    padding: "15px",
    color: active ? "#fff" : "#4A6FA5",
    fontWeight: 700,
    fontSize: "1rem",
    cursor: active && !isLoading ? "pointer" : "not-allowed",
    boxShadow: active ? "0 8px 32px rgba(0,102,255,0.35)" : "none",
    transition: "all 0.2s",
  });

  return (
    <div style={{
      background: "linear-gradient(135deg, rgba(8,15,30,0.95), rgba(5,10,20,0.95))",
      border: "1px solid rgba(0,102,255,0.2)",
      borderRadius: 20,
      padding: "32px 28px",
      display: "flex",
      flexDirection: "column",
      gap: 24,
    }}>
      <div>
        <h3 style={{ fontWeight: 800, fontSize: "1.15rem", marginBottom: 4 }}>Deposit USDC</h3>
        <p style={{ color: "#4A6FA5", fontSize: "0.82rem", lineHeight: 1.5 }}>
          Approve USDC then open a ranged position. Idle capital auto-routes to Compound V3.
        </p>
      </div>

      {/* ── Done ── */}
      {step === "done" && (
        <div style={{ background: "rgba(0,200,100,0.08)", border: "1px solid rgba(0,200,100,0.25)", borderRadius: 12, padding: "16px 20px" }}>
          <div style={{ fontWeight: 700, color: "#00C864", fontSize: "0.95rem", marginBottom: 6 }}>Position opened!</div>
          <p style={{ color: "#4A6FA5", fontSize: "0.8rem", marginBottom: 12 }}>
            Your USDC is in the pool. If the price exits your range, StableStream will auto-route it to yield.
          </p>
          {depositHash && (
            <a href={`https://sepolia.uniscan.xyz/tx/${depositHash}`} target="_blank" rel="noopener noreferrer"
              style={{ fontSize: "0.75rem", color: "#00AAFF", display: "block", marginBottom: 12 }}
              aria-label="View deposit transaction on Uniscan (opens in new tab)">
              View deposit tx ↗
            </a>
          )}
          <button type="button" onClick={resetForm}
            style={{ background: "rgba(0,102,255,0.12)", border: "1px solid rgba(0,102,255,0.3)", borderRadius: 8, padding: "8px 16px", color: "#00AAFF", fontWeight: 600, fontSize: "0.82rem", cursor: "pointer" }}>
            New deposit
          </button>
        </div>
      )}

      {/* ── Error ── */}
      {step === "error" && (
        <div role="alert" style={{ background: "rgba(255,80,80,0.08)", border: "1px solid rgba(255,80,80,0.25)", borderRadius: 12, padding: "14px 18px" }}>
          <div style={{ fontWeight: 700, color: "#FF5050", fontSize: "0.9rem", marginBottom: 6 }}>Transaction failed</div>
          <p style={{ color: "#4A6FA5", fontSize: "0.78rem", wordBreak: "break-word", marginBottom: 12 }}>{errorMsg}</p>
          <button type="button" onClick={resetForm}
            style={{ background: "rgba(255,80,80,0.1)", border: "1px solid rgba(255,80,80,0.3)", borderRadius: 8, padding: "8px 16px", color: "#FF5050", fontWeight: 600, fontSize: "0.82rem", cursor: "pointer" }}>
            Dismiss
          </button>
        </div>
      )}

      {step !== "done" && (
        <>
          {/* ── USDC amount ── */}
          <div>
            <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 8 }}>
              <label htmlFor="usdc-amount" style={{ fontSize: "0.8rem", color: "#4A6FA5", fontWeight: 600, letterSpacing: "0.5px" }}>
                USDC AMOUNT
              </label>
              <span style={{ fontSize: "0.78rem", color: "#4A6FA5" }}>
                Balance: <span style={{ color: "#F0F4FF", fontWeight: 600 }}>{balanceFmt} USDC</span>
              </span>
            </div>
            <div style={{ position: "relative" }}>
              <input
                id="usdc-amount"
                type="number"
                min="0"
                step="any"
                placeholder="0.00"
                value={usdcInput}
                onChange={(e) => setUsdcInput(e.target.value)}
                disabled={isLoading}
                style={{
                  width: "100%",
                  background: "rgba(0,102,255,0.06)",
                  border: "1px solid rgba(0,102,255,0.2)",
                  borderRadius: 12,
                  padding: "14px 80px 14px 16px",
                  fontSize: "1.15rem",
                  fontWeight: 700,
                  color: "#F0F4FF",
                  outline: "none",
                  opacity: isLoading ? 0.5 : 1,
                }}
              />
              <button
                type="button"
                disabled={isLoading || !balance}
                onClick={() => balance !== undefined && setUsdcInput(formatUnits(balance as bigint, USDC_DECIMALS))}
                style={{
                  position: "absolute", right: 12, top: "50%", transform: "translateY(-50%)",
                  background: "rgba(0,102,255,0.15)", border: "1px solid rgba(0,102,255,0.3)", borderRadius: 8,
                  padding: "6px 12px", color: "#00AAFF", fontWeight: 700, fontSize: "0.75rem",
                  cursor: isLoading ? "not-allowed" : "pointer",
                }}>
                MAX
              </button>
            </div>
            {parsedAmount > 0n && !hasBalance && (
              <p style={{ color: "#FF5050", fontSize: "0.76rem", marginTop: 6 }}>Insufficient USDC balance</p>
            )}
          </div>

          {/* ── Tick range ── */}
          <div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 10 }}>
              <label style={{ fontSize: "0.8rem", color: "#4A6FA5", fontWeight: 600, letterSpacing: "0.5px" }}>
                TICK RANGE
              </label>
              <TicksExplainer />
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
              {TICK_RANGES.map((r, i) => (
                <button key={r.label} type="button" disabled={isLoading} onClick={() => setRangeIdx(i)}
                  style={{
                    background: rangeIdx === i ? "rgba(0,102,255,0.18)" : "rgba(0,102,255,0.05)",
                    border: `1px solid ${rangeIdx === i ? "rgba(0,170,255,0.5)" : "rgba(0,102,255,0.15)"}`,
                    borderRadius: 10, padding: "10px 8px",
                    color: rangeIdx === i ? "#00AAFF" : "#4A6FA5",
                    fontWeight: rangeIdx === i ? 700 : 500, fontSize: "0.78rem",
                    cursor: isLoading ? "not-allowed" : "pointer", transition: "all 0.2s", textAlign: "left",
                  }}>
                  {r.label}
                </button>
              ))}
            </div>
            <p style={{ color: "#4A6FA5", fontSize: "0.75rem", marginTop: 8 }}>
              Ticks {range.tickLower} → {range.tickUpper} · Closer range = higher fee earn rate
            </p>
          </div>

          {/* ── Step indicator ── */}
          <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
            {([
              { num: 1, label: "Approve USDC",  done: !needsApprove },
              { num: 2, label: "Open Position", done: depositConfirmed },
            ] as const).map((s) => (
              <div key={s.num} style={{ display: "flex", alignItems: "center", gap: 6, flex: 1 }}>
                <div style={{
                  width: 24, height: 24, borderRadius: "50%",
                  background: s.done ? "rgba(0,200,100,0.15)" : "rgba(0,102,255,0.1)",
                  border: `1px solid ${s.done ? "#00C864" : "rgba(0,102,255,0.3)"}`,
                  display: "flex", alignItems: "center", justifyContent: "center",
                  fontSize: "0.7rem", fontWeight: 800,
                  color: s.done ? "#00C864" : "#4A6FA5",
                  flexShrink: 0,
                }}>
                  {s.done ? "✓" : s.num}
                </div>
                <span style={{ fontSize: "0.78rem", color: s.done ? "#00C864" : "#4A6FA5", fontWeight: s.done ? 600 : 400 }}>
                  {s.label}
                </span>
              </div>
            ))}
          </div>

          {/* ── Action button ── */}
          {needsApprove ? (
            <button type="button" disabled={isLoading || !canAct} onClick={handleApprove}
              aria-busy={step === "approving"} style={btnStyle(canAct && !isLoading)}>
              {step === "approving" ? "Approving…" : "Step 1: Approve USDC"}
            </button>
          ) : (
            <button type="button" disabled={isLoading || !canAct} onClick={handleDeposit}
              aria-busy={step === "depositing"} style={btnStyle(canAct && !isLoading)}>
              {step === "depositing" ? "Opening position…" : "Step 2: Open Position"}
            </button>
          )}

          {/* ── Pending tx link ── */}
          {approveHash && step === "approving" && (
            <a href={`https://sepolia.uniscan.xyz/tx/${approveHash}`} target="_blank" rel="noopener noreferrer"
              style={{ fontSize: "0.75rem", color: "#00AAFF", textDecoration: "none", textAlign: "center" }}
              aria-label="View approve transaction on Uniscan (opens in new tab)">
              Approve tx pending — view on Uniscan ↗
            </a>
          )}
          {depositHash && step === "depositing" && (
            <a href={`https://sepolia.uniscan.xyz/tx/${depositHash}`} target="_blank" rel="noopener noreferrer"
              style={{ fontSize: "0.75rem", color: "#00AAFF", textDecoration: "none", textAlign: "center" }}
              aria-label="View deposit transaction on Uniscan (opens in new tab)">
              Deposit tx pending — view on Uniscan ↗
            </a>
          )}
        </>
      )}
    </div>
  );
}
