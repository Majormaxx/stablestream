import { createConfig, http } from "wagmi";
import { injected, metaMask } from "wagmi/connectors";
import { UNICHAIN_SEPOLIA } from "./contracts";

// RPC URL is configurable via NEXT_PUBLIC_RPC_URL env var (Finding d11b1407).
// Falls back to the public Unichain Sepolia endpoint when the env var is not set.
const rpcUrl = process.env.NEXT_PUBLIC_RPC_URL ?? "https://sepolia.unichain.org";

export const wagmiConfig = createConfig({
  chains: [UNICHAIN_SEPOLIA],
  connectors: [injected(), metaMask()],
  transports: {
    [UNICHAIN_SEPOLIA.id]: http(rpcUrl),
  },
});
