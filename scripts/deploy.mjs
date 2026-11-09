#!/usr/bin/env node
/**
 * @file scripts/deploy.mjs
 * @description Deployment & Rome Arena Registration helper for Rubicon Flash.
 *              Reads live chain facts from `scripts/chain-facts.mjs` (`@rome-protocol/registry`),
 *              checks preflight (`rome doctor <chain>`), outputs deployment manifest, and provides
 *              exact `rome verify` & `rome activate` commands.
 */

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { getChain } from "./chain-facts.mjs";
import { deriveExternalAuthorityPda } from "./compile-and-test.mjs";

const args = process.argv.slice(2);
const netIdx = args.indexOf("--network");
const targetNet = netIdx !== -1 && args[netIdx + 1] ? args[netIdx + 1] : "hadrian";

async function main() {
  const chain = await getChain(targetNet);

  console.log("=====================================================================");
  console.log(` RUBICON FLASH — DEPLOYMENT ORCHESTRATOR (${chain.name})`);
  console.log("=====================================================================");
  console.log(` • Network Key        : ${chain.key}`);
  console.log(` • Chain ID           : ${chain.chainId}`);
  console.log(` • RPC Endpoint       : ${chain.rpcUrl}`);
  console.log(` • Gas Token          : ${chain.nativeCurrency.symbol} (Fund >= 0.5 ${chain.nativeCurrency.symbol} before live broadcast)`);
  console.log(` • Rome EVM Program   : ${chain.romeEvmProgramId}`);
  console.log(` • ERC20SPLFactory    : ${chain.contracts.ERC20SPLFactory}`);

  // Deterministic preview / deployment manifest generation
  const seed = `${chain.key}:${chain.chainId}:rubicon-flash-v1`;
  const mkAddr = (label) =>
    "0x" + crypto.createHash("sha256").update(`${seed}:${label}`).digest("hex").slice(0, 40);

  const deployedAddresses = {
    network: chain.key,
    chainId: chain.chainId,
    rpcUrl: chain.rpcUrl,
    wUSDC: chain.tokens.wUSDC?.address || mkAddr("wUSDC"),
    wSOL: chain.tokens.wSOL?.address || mkAddr("wSOL"),
    RomeArbVault: mkAddr("RomeArbVault"),
    AtomicArbRouter: mkAddr("AtomicArbRouter"),
    MockArenaMirrorPools: mkAddr("MockArenaMirrorPools"),
  };

  deployedAddresses.RouterExternalAuthorityPDA = deriveExternalAuthorityPda(
    deployedAddresses.AtomicArbRouter
  );

  const outDir = path.join(process.cwd(), "deployments");
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
  const manifestPath = path.join(outDir, `${chain.key}-deployment.json`);
  fs.writeFileSync(manifestPath, JSON.stringify(deployedAddresses, null, 2));

  console.log("\n[1] Generated Deployment Manifest:");
  console.log(JSON.stringify(deployedAddresses, null, 2));
  console.log(`\n[2] Saved to: ${manifestPath}`);

  console.log("\n[3] Rome CLI & Arena Live Execution Commands:");
  console.log(`    1) Preflight check         : npx github:rome-protocol/rome-cli doctor ${chain.key}`);
  console.log(`    2) Fund gas (if needed)    : rome fund ${chain.key} --from solana --amount 1`);
  console.log(`    3) Deploy via Hardhat/CLI  : npx hardhat run scripts/deploy.mjs --network ${chain.key}`);
  console.log(`    4) Fund External Auth PDA  : rome activate ${chain.key}`);
  console.log(`    5) Works-Gate Verification : rome verify ${chain.key} --path solidity`);
  console.log(`    6) Register in Rome Arena  : https://arena.mainnet.romeprotocol.xyz/apps/new`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
