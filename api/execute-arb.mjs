import {
  getRuntime,
  ACTIVE_USER,
  SOLANA_WELL_KNOWN_PROGRAMS,
  deriveExternalAuthorityPda,
} from "./_runtime.mjs";

export default async function handler(req, res) {
  const runtime = getRuntime();
  try {
    const body = typeof req.body === "string" ? JSON.parse(req.body || "{}") : req.body || {};
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

    res.status(200).json({ ok: true, result });
  } catch (err) {
    res.status(400).json({ ok: false, error: err.message });
  }
}
