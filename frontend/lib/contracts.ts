import YieldRouterABI from "./abis/YieldRouter.json";
import StableStreamHookABI from "./abis/StableStreamHook.json";
import StableStreamNFTABI from "./abis/StableStreamNFT.json";
import CompoundV3AdapterABI from "./abis/CompoundV3Adapter.json";

export const UNICHAIN_SEPOLIA = {
  id: 1301,
  name: "Unichain Sepolia",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://sepolia.unichain.org"] },
  },
  blockExplorers: {
    default: { name: "Uniscan", url: "https://sepolia.uniscan.xyz" },
  },
} as const;

export const CONTRACTS = {
  YIELD_ROUTER:    "0xc69a63B6FbB684f1aC47BDe6613ed49B66A9feeA" as `0x${string}`,
  COMPOUND_ADAPTER:"0x67fD183808Dc4B886b20946456F3fD81f488D2d7" as `0x${string}`,
  HOOK:            "0xDB23B8Ff772fC1e29EB35a4BECe17f6D1a9A86C0" as `0x${string}`,
  NFT:             "0x6f265EB778C44118cfc8484cA44A2Ea216ea998C" as `0x${string}`,
  USDC:            "0x31d0220469e10c4E71834a79b1f276d740d3768F" as `0x${string}`,
  POOL_MANAGER:    "0x00B036B58a818B1BC34d502D3fE730Db729e62AC" as `0x${string}`,
} as const;

export const POOL_ID = "0x2af851d6f565ece7e573e814a3c453b0f75b4f56a55307e6dffdc0f91bb3ebed";

export { YieldRouterABI, StableStreamHookABI, StableStreamNFTABI, CompoundV3AdapterABI };
