import { getRuntime, ACTIVE_USER } from "./_runtime.mjs";

export default async function handler(req, res) {
  const runtime = getRuntime();
  runtime._registerUser(
    ACTIVE_USER,
    "0x99887766554433221100aabbccddeeff99887766554433221100aabbccddeeff"
  );
  res.status(200).json({ ok: true, totalUniqueUsers: runtime.totalUniqueUsers });
}
