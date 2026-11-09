import { getRuntime, ACTIVE_USER, getChain, runArbitrageSimulationCycle } from "./_runtime.mjs";

export default async function handler(req, res) {
  const runtime = getRuntime();
  const network = req.query?.network || "hadrian";
  const uniPrice = parseFloat(req.query?.uniPrice || "180.00");
  const meteoraPrice = parseFloat(req.query?.meteoraPrice || "184.95");
  const principalUsdc = parseFloat(req.query?.principal || "10000");
  const minProfitUsdc = parseFloat(req.query?.minProfit || "25");

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

  res.status(200).json({
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
}
