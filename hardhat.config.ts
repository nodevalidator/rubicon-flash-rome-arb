import { defineConfig, configVariable } from "hardhat/config";

/**
 * Rome Protocol Hardhat Configuration
 * Always verify live RPC / Chain IDs using `rome facts chain <name>` or `npm run facts:hadrian`
 * Generated compatible with `rome preset foundry/hardhat hadrian`
 */
export default defineConfig({
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  networks: {
    hadrian: {
      type: "http",
      chainType: "l1",
      chainId: Number(process.env.ROME_HADRIAN_CHAIN_ID || 200010),
      url: process.env.ROME_HADRIAN_RPC || "https://hadrian.testnet.romeprotocol.xyz/",
      accounts: process.env.ROME_EVM_KEY ? [process.env.ROME_EVM_KEY] : [configVariable("PRIVATE_KEY")],
    },
    rubicon: {
      type: "http",
      chainType: "l1",
      chainId: Number(process.env.ROME_RUBICON_CHAIN_ID || 7531),
      url: process.env.ROME_RUBICON_RPC || "https://rubicon.mainnet.romeprotocol.xyz/",
      accounts: process.env.ROME_EVM_KEY ? [process.env.ROME_EVM_KEY] : [configVariable("PRIVATE_KEY")],
    },
    ostia: {
      type: "http",
      chainType: "l1",
      chainId: Number(process.env.ROME_OSTIA_CHAIN_ID || 770101),
      url: process.env.ROME_OSTIA_RPC || "https://ostia.devnet.romeprotocol.xyz/rpc",
      accounts: process.env.ROME_EVM_KEY ? [process.env.ROME_EVM_KEY] : [configVariable("PRIVATE_KEY")],
    },
  },
});
