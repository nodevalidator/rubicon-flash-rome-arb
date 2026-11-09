#!/usr/bin/env node
/**
 * @file server.mjs
 * @description Rubicon Flash — Dual-Lane Interactive Web Server & API.
 *              Serves the Dual-Lane Dashboard (`frontend/index.html`) and connects live
 *              `@rome-protocol/registry` facts + the `RubiconFlashRuntimeEmulator` state engine.
 */

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { URL } from "node:url";
import { getChain, SOLANA_WELL_KNOWN_PROGRAMS } from "./scripts/chain-facts.mjs";
import {
  RubiconFlashRuntimeEmulator,
  deriveExternalAuthorityPda,
} from "./scripts/compile-and-test.mjs";
import { runArbitrageSimulationCycle } from "./scripts/arb-bot.mjs";

const PORT = Number(process.env.PORT || 3000);
const ACTIVE_USER = "0x71C8000000000000000000000000000000009A2E";
const INSTITUTIONAL_SEED_LP = "0x1111111111111111111111111111111111111111";

// Initialize persistent stateful engine for interactive dashboard session
const runtime = new RubiconFlashRuntimeEmulator({
  uniSolPriceUsdcE6: 180_000_000n,
  meteoraSolPriceUsdcE6: 184_950_000n,
});

// Seed initial Shared Vault TVL ($150,000 wUSDC) and give active user $25,000 wUSDC test balance
runtime.mintUsdcToUser(INSTITUTIONAL_SEED_LP, 150_000_000_000n);
runtime.deposit(INSTITUTIONAL_SEED_LP, 150_000_000_000n);
runtime.mintUsdcToUser(ACTIVE_USER, 25_000_000_000n);

function readJsonBody(req) {
  return new Promise((resolve) => {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      try {
        resolve(JSON.parse(body || "{}"));
      } catch {
        resolve({});
      }
    });
  });
}

function sendJson(res, status, payload) {
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(payload));
}

const server = http.createServer(async (req, res) => {
  const parsedUrl = new URL(req.url, `http://localhost:${PORT}`);
  const pathname = parsedUrl.pathname;

  if (pathname === "/" || pathname === "/index.html") {
    const htmlPath = path.join(process.cwd(), "frontend", "index.html");
    const html = fs.readFileSync(htmlPath, "utf8");
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(html);
    return;
  }

  if (pathname === "/api/state" && req.method === "GET") {
    const network = parsedUrl.searchParams.get("network") || "hadrian";
    const uniPrice = parseFloat(parsedUrl.searchParams.get("uniPrice") || "180.00");
    const meteoraPrice = parseFloat(parsedUrl.searchParams.get("meteoraPrice") || "184.95");
    const principalUsdc = parseFloat(parsedUrl.searchParams.get("principal") || "10000");
    const minProfitUsdc = parseFloat(parsedUrl.searchParams.get("minProfit") || "25");

    const chain = await getChain(network);
    const simulation = await runArbitrageSimulationCycle({
      network,
      principalUsdc,
      minProfitUsdc,
      uniPrice,
      meteoraPrice,
    });

    const userSharesE6 = runtime.vaultSharesByUser.get(ACTIVE_USER) || 0n;
    const userAssetsValueE6 = runtime.convertToAssets(userSharesE6);
    const userWalletUsdcE6 = runtime.userWalletUsdc.get(ACTIVE_USER) || 0n;

    sendJson(res, 200, {
      chain,
      simulation,
      vault: {
        totalAssetsUsdc: Number(runtime.vaultTotalAssets) / 1e6,
        totalShares: Number(runtime.vaultTotalShares) / 1e6,
        sharePrice: Number(runtime.sharePriceE6()) / 1e6,
        totalUniqueUsers: runtime.totalUniqueUsers,
        totalArbitrageVolumeUsdc: Number(runtime.totalArbitrageVolume) / 1e6,
        totalCumulativeYieldUsdc: Number(runtime.totalCumulativeYield) / 1e6,
        totalKeeperBountiesUsdc: Number(runtime.totalKeeperBountiesPaid) / 1e6,
        totalArbTradesCount: runtime.totalArbTradesCount,
      },
      user: {
        address: ACTIVE_USER,
        walletUsdc: Number(userWalletUsdcE6) / 1e6,
        vaultShares: Number(userSharesE6) / 1e6,
        vaultAssetsValueUsdc: Number(userAssetsValueE6) / 1e6,
      },
      recentLogs: runtime.cpiDispatchLogs.slice(-10),
    });
    return;
  }

  if (pathname === "/api/link-wallet" && req.method === "POST") {
    runtime._registerUser(
      ACTIVE_USER,
      "0x99887766554433221100aabbccddeeff99887766554433221100aabbccddeeff"
    );
    sendJson(res, 200, { ok: true, totalUniqueUsers: runtime.totalUniqueUsers });
    return;
  }

  if (pathname === "/api/deposit" && req.method === "POST") {
    const body = await readJsonBody(req);
    try {
      const amountE6 = BigInt(Math.round(Number(body.amountUsdc || 0) * 1_000_000));
      const shares = runtime.deposit(
        ACTIVE_USER,
        amountE6,
        "0x99887766554433221100aabbccddeeff99887766554433221100aabbccddeeff"
      );
      sendJson(res, 200, { ok: true, sharesMintedE6: shares.toString() });
    } catch (err) {
      sendJson(res, 400, { ok: false, error: err.message });
    }
    return;
  }

  if (pathname === "/api/withdraw" && req.method === "POST") {
    const body = await readJsonBody(req);
    try {
      const sharesE6 = BigInt(Math.round(Number(body.shares || 0) * 1_000_000));
      const assetsOut = runtime.withdraw(ACTIVE_USER, sharesE6);
      sendJson(res, 200, { ok: true, assetsOutE6: assetsOut.toString() });
    } catch (err) {
      sendJson(res, 400, { ok: false, error: err.message });
    }
    return;
  }

  if (pathname === "/api/execute-arb" && req.method === "POST") {
    const body = await readJsonBody(req);
    try {
      const uniPrice = Number(body.uniPrice || 180.0);
      const meteoraPrice = Number(body.meteoraPrice || 184.95);
      runtime.uniSolPriceUsdcE6 = BigInt(Math.round(uniPrice * 1_000_000));
      runtime.meteoraSolPriceUsdcE6 = BigInt(Math.round(meteoraPrice * 1_000_000));

      const direction = meteoraPrice >= uniPrice ? "EVM_TO_SOLANA" : "SOLANA_TO_EVM";
      const externalPda = deriveExternalAuthorityPda(runtime.routerAddress);

      const solanaAccounts = [
        { pubkey: "0x11".repeat(32).slice(0, 66), isSigner: false, isWritable: true },
        { pubkey: "0x22".repeat(32).slice(0, 66), isSigner: false, isWritable: true },
        { pubkey: "0x33".repeat(32).slice(0, 66), isSigner: false, isWritable: true },
        { pubkey: "0x44".repeat(32).slice(0, 66), isSigner: false, isWritable: true },
        { pubkey: "0x55".repeat(32).slice(0, 66), isSigner: false, isWritable: true },
        { pubkey: externalPda, isSigner: true, isWritable: false },
        { pubkey: SOLANA_WELL_KNOWN_PROGRAMS.SPL_TOKEN_PROGRAM_BYTES32, isSigner: false, isWritable: false },
      ];

      const result = runtime.executeAtomicArbitrage({
        executor: ACTIVE_USER,
        userSolanaPubkey: "0x99887766554433221100aabbccddeeff99887766554433221100aabbccddeeff",
        direction,
        capitalSource: body.capitalSource || "SHARED_VAULT",
        amountInE6: BigInt(Math.round(Number(body.principalUsdc || 10000) * 1_000_000)),
        minProfitE6: BigInt(Math.round(Number(body.minProfitUsdc || 25) * 1_000_000)),
        estimatedCpiDepth: 2,
        solanaAccounts,
      });

      sendJson(res, 200, { ok: true, result });
    } catch (err) {
      sendJson(res, 400, { ok: false, error: err.message });
    }
    return;
  }

  sendJson(res, 404, { error: "Not found" });
});

server.listen(PORT, () => {
  console.log("=====================================================================");
  console.log(` RUBICON FLASH — DUAL-LANE DASHBOARD LIVE AT http://localhost:${PORT}`);
  console.log("=====================================================================");
});
