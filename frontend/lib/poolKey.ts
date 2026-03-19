import { CONTRACTS } from "./contracts";

// The ETH/USDC pool initialized via InitPool.s.sol
export const POOL_KEY = {
  currency0:   "0x0000000000000000000000000000000000000000" as `0x${string}`,
  currency1:   CONTRACTS.USDC,
  fee:         500,
  tickSpacing: 10,
  hooks:       CONTRACTS.HOOK,
} as const;

// USDC has 6 decimals on Unichain
export const USDC_DECIMALS = 6;
export const USDC_UNIT = 10 ** USDC_DECIMALS; // 1 USDC = 1_000_000

// Preset tick ranges for USDC-only range orders on an ETH/USDC pool at tick = 0.
//
// Pool state:  currency0 = ETH (native), currency1 = USDC, initialised at sqrtPrice = 2^96 (tick 0).
//
// For a USDC-only deposit the position range must be ENTIRELY BELOW the current tick so that
// sqrtPrice ≥ sqrtPriceAtTick(tickUpper) — i.e. the whole range is already "above price" and
// therefore 100% token1 (USDC).  Symmetric ranges like ±10 straddle tick 0, putting the
// position in-range and requiring the hook to provide ETH it does not hold → revert.
//
// All ticks must be multiples of tickSpacing (10).
export const TICK_RANGES = [
  { label: "Tight  (-20 → -10)",    tickLower: -20,    tickUpper: -10   },
  { label: "Medium (-60 → -10)",    tickLower: -60,    tickUpper: -10   },
  { label: "Wide   (-210 → -10)",   tickLower: -210,   tickUpper: -10   },
  { label: "Full   (-887220 → -10)",tickLower: -887220, tickUpper: -10  },
] as const;
