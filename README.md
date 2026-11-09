# Rubicon Flash — Dual-Lane Atomic Arbitrage Router & Shared Vault

> **Built for the Rome Protocol Builder Arena (`Hadrian Testnet 200010` → `Rubicon Mainnet 7531`)**
> *Tagline: "EVM and Solana, One Market — Zero-Leg-Risk Atomic Arbitrage in a Single ~400ms Solana Transaction."*

---

## 1. Why Rubicon Flash Wins in Rome Builder Arena

Rome Arena ranks projects from **Legionary → Patrician → Pontifex Maximus** based on three real on-chain metrics: **Value Locked (TVL)**, **Transaction Volume**, and **User Acquisition**.

**Rubicon Flash** is engineered to compound all three metrics simultaneously while showcasing capabilities that **only Rome Protocol can execute**:

1. **Atomic EVM ⇄ Solana CPI Execution (`0xFF...08`):**
   - Leg 1 executes on a Rome EVM DEX (**Uniswap V3**).
   - Leg 2 invokes a native Solana AMM (**Meteora DAMM / SPL**) via Rome's `ICrossProgramInvocation` precompile (`0xFF00000000000000000000000000000000000008`) using `invoke_signed` and a 24-byte Little-Endian Borsh payload.
   - **Atomic Profit Guard:** If `balanceAfter < balanceBefore + minProfit`, the **entire transaction reverts across both EVM and Solana**. Zero bridge latency, zero leg risk.
2. **Dual-Capital Engine (`RomeArbVault.sol` + `AtomicArbRouter.sol`):**
   - **Shared Liquidity Vault (TVL Driver):** Users from either **MetaMask (EVM Lane)** or **Phantom (Solana Lane)** deposit `wUSDC` into `RomeArbVault` to mint yield-bearing `rvUSDC` shares.
   - **1-Click Keeper Bounty (Volume & User Driver):** Any user can trigger an arbitrage trade using the Vault's flash liquidity with **zero upfront capital**. Net profits are split **80% to Vault LPs** (auto-compounding `rvUSDC` share price) and **20% paid instantly to the Keeper/User**.

---

## 2. Project Structure

- [`contracts/interfaces/IRomePrecompiles.sol`](contracts/interfaces/IRomePrecompiles.sol) — Canonical interfaces for `ISystemProgram` (`0xFF...07`), `ICrossProgramInvocation` (`0xFF...08`), and `IHelperProgram` (`0xFF...09`).
- [`contracts/interfaces/IUniswapV3AndMeteora.sol`](contracts/interfaces/IUniswapV3AndMeteora.sol) — `IERC20SPLFactory`, `IUniswapV3SwapRouter`, `IMeteoraDAMMPool`, and `BorshSolanaSwapCodec` (Little-Endian `uint64` + Anchor sighash encoder).
- [`contracts/RomeArbVault.sol`](contracts/RomeArbVault.sol) — Dual-Lane ERC-4626 Shared Liquidity Pool with 80/20 profit split and Arena telemetry counters.
- [`contracts/AtomicArbRouter.sol`](contracts/AtomicArbRouter.sol) — Core Atomic Arbitrage Executor enforcing upfront `AccountMeta[]` declaration, `CPI_DEPTH <= 4`, and Atomic Profit Guard.
- [`contracts/MockArenaPools.sol`](contracts/MockArenaPools.sol) — Configurable spread pools on Hadrian Testnet so anyone testing your app can always trigger profitable atomic trades on demand.
- [`scripts/chain-facts.mjs`](scripts/chain-facts.mjs) — Dynamic `@rome-protocol/registry` resolver (never hardcodes chain IDs or contract addresses).
- [`scripts/compile-and-test.mjs`](scripts/compile-and-test.mjs) — Complete test suite & artifact generator.
- [`scripts/arb-bot.mjs`](scripts/arb-bot.mjs) — CLI Arbitrage Engine, Simulator & Keeper Bot.
- [`scripts/deploy.mjs`](scripts/deploy.mjs) — Deployment orchestrator for Hadrian (`200010`) and Rubicon (`7531`).
- [`frontend/index.html`](frontend/index.html) & [`server.mjs`](server.mjs) — Interactive Dual-Lane Web Dashboard (MetaMask + Phantom lanes, Spread Radar, CPI Inspector, Vault UI).

---

## 3. Quick Start Commands

```bash
# 1. Run the Solidity validation & 6-part Atomic Arbitrage unit test suite
node scripts/compile-and-test.mjs

# 2. Inspect dynamic Rome Registry facts for Hadrian Testnet or Rubicon Mainnet
node scripts/chain-facts.mjs hadrian
node scripts/chain-facts.mjs rubicon

# 3. Run the Arbitrage Simulator & Keeper Bot
node scripts/arb-bot.mjs

# 4. Generate deployment manifests & Rome CLI verification commands
node scripts/deploy.mjs --network hadrian
node scripts/deploy.mjs --network rubicon

# 5. Launch the Interactive Dual-Lane Web Dashboard (http://localhost:3000)
node server.mjs
```

---

## 4. Official Rome Arena Submission Checklist (`Learn → Build → Win`)

1. **Preflight Hadrian Testnet:**
   ```bash
   npx github:rome-protocol/rome-cli doctor hadrian
   ```
2. **Fund Testnet Gas (`>= 0.5 USDC` on Hadrian):**
   ```bash
   rome fund hadrian --from solana --amount 1
   ```
3. **Deploy Contracts & Activate External-Authority PDA:**
   ```bash
   export PRIVATE_KEY="0x..."
   npx hardhat run scripts/deploy.mjs --network hadrian
   rome activate hadrian
   ```
4. **Pass Works-Gate Verification:**
   ```bash
   rome verify hadrian --path solidity
   ```
5. **Register in Rome Arena:**
   Submit your app and link `RomeArbVault` + `AtomicArbRouter` at `https://arena.mainnet.romeprotocol.xyz/apps/new`.
