import { getChain, SOLANA_WELL_KNOWN_PROGRAMS } from "../scripts/chain-facts.mjs";
import {
  RubiconFlashRuntimeEmulator,
  deriveExternalAuthorityPda,
} from "../scripts/compile-and-test.mjs";
import { runArbitrageSimulationCycle } from "../scripts/arb-bot.mjs";

const ACTIVE_USER = "0x71C8000000000000000000000000000000009A2E";
const INSTITUTIONAL_SEED_LP = "0x1111111111111111111111111111111111111111";

// Global singleton inside serverless warm instance
if (!globalThis.__rubiconFlashRuntime) {
  const rt = new RubiconFlashRuntimeEmulator({
    uniSolPriceUsdcE6: 180_000_000n,
    meteoraSolPriceUsdcE6: 184_950_000n,
  });
  rt.mintUsdcToUser(INSTITUTIONAL_SEED_LP, 150_000_000_000n);
  rt.deposit(INSTITUTIONAL_SEED_LP, 150_000_000_000n);
  rt.mintUsdcToUser(ACTIVE_USER, 25_000_000_000n);
  globalThis.__rubiconFlashRuntime = rt;
}

export function getRuntime() {
  return globalThis.__rubiconFlashRuntime;
}

export { ACTIVE_USER, SOLANA_WELL_KNOWN_PROGRAMS, deriveExternalAuthorityPda, getChain, runArbitrageSimulationCycle };
