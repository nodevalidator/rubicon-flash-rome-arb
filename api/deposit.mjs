import { getRuntime, ACTIVE_USER } from "./_runtime.mjs";

export default async function handler(req, res) {
  const runtime = getRuntime();
  try {
    const body = typeof req.body === "string" ? JSON.parse(req.body || "{}") : req.body || {};
    const amountE6 = BigInt(Math.round(Number(body.amountUsdc || 0) * 1_000_000));
    const shares = runtime.deposit(
      ACTIVE_USER,
      amountE6,
      "0x99887766554433221100aabbccddeeff99887766554433221100aabbccddeeff"
    );
    res.status(200).json({ ok: true, sharesMintedE6: shares.toString() });
  } catch (err) {
    res.status(400).json({ ok: false, error: err.message });
  }
}
