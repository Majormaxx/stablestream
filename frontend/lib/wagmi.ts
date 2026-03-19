import { createConfig, http } from "wagmi";
import { injected, metaMask } from "wagmi/connectors";
import { UNICHAIN_SEPOLIA } from "./contracts";

export const wagmiConfig = createConfig({
  chains: [UNICHAIN_SEPOLIA],
  connectors: [injected(), metaMask()],
  transports: {
    [UNICHAIN_SEPOLIA.id]: http("https://sepolia.unichain.org"),
  },
});
