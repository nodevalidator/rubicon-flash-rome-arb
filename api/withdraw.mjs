import { getRuntime, ACTIVE_USER } from "./_runtime.mjs";

export default async function handler(req, res) {
  const runtime = getRuntime();
  try {
    const body = typeof req.body === "string" ? JSON.parse(req.body || "{}") : req.body || {};
    const sharesE6 = BigInt(Math.round(Number(body.shares || 0) * 1_000_000));
    const assetsOut = runtime.withdraw(ACTIVE_USER, sharesE6);
    res.status(200).json({ ok: true, assetsOutE6: assetsOut.toString() });
  } catch (err) {
    res.status(400).json({ ok: false, error: err.message });
  }
}
