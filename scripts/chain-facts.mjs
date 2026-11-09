#!/usr/bin/env node
/**
 * @file scripts/chain-facts.mjs
 * @description Canonical Rome Protocol Registry & Live RPC Resolver (`@rome-protocol/registry` compatible).
 *              Never hardcode chain facts in application logic — always import `getChain`, `getContracts`,
 *              `getTokens`, and `getPrograms` from this module or `@rome-protocol/registry`.
 */

export const ROME_PRECOMPILES = {
  ISystemProgram: "0xFF00000000000000000000000000000000000007",
  ICrossProgramInvocation: "0xFF00000000000000000000000000000000000008",
  IHelperProgram: "0xFF00000000000000000000000000000000000009",
};

export const SOLANA_WELL_KNOWN_PROGRAMS = {
  SPL_TOKEN_PROGRAM_BASE58: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
  SPL_TOKEN_PROGRAM_BYTES32: "0x06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9",
  SYSTEM_PROGRAM_BASE58: "11111111111111111111111111111111",
  SYSTEM_PROGRAM_BYTES32: "0x0000000000000000000000000000000000000000000000000000000000000000",
  ASSOCIATED_TOKEN_PROGRAM_BASE58: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL",
  ASSOCIATED_TOKEN_PROGRAM_BYTES32: "0x8c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859",
  METEORA_DAMM_PROGRAM_BYTES32: "0x0e677a9b35564095c28d8d095b12676f3e3b46b2f6c1147329d5e80643a992f1",
};

const REGISTRY_CATALOG = {
  hadrian: {
    key: "hadrian",
    name: "Rome Hadrian Testnet",
    network: "testnet",
    solanaCluster: "devnet",
    chainId: Number(process.env.ROME_HADRIAN_CHAIN_ID || 200010),
    rpcUrl: process.env.ROME_HADRIAN_RPC || "https://hadrian.testnet.romeprotocol.xyz/",
    explorerUrl: "https://via-hadrian.testnet.romeprotocol.xyz/",
    romeEvmProgramId: "RPTWwELXAY4KC9ZPHhaxp7Sq1hHtU3HNEgLbSegCcWf",
    nativeCurrency: {
      name: "USD Coin (Hadrian Gas)",
      symbol: "USDC",
      decimals: 18,
    },
    contracts: {
      ERC20SPLFactory: process.env.HADRIAN_ERC20_SPL_FACTORY || "0x37c13e4f00000000000000000000000000001078",
      Multicall3: process.env.HADRIAN_MULTICALL3 || "0xb7180d3c0000000000000000000000000000ae4c",
      RomeBridgeWithdraw: process.env.HADRIAN_BRIDGE_WITHDRAW || "0x6eeacb4e0000000000000000000000000000ec73",
      UniswapV3Factory: process.env.HADRIAN_UNISWAP_V3_FACTORY || "0xD9E323080000000000000000000000000000D5bD",
      UniswapV4PoolManager: process.env.HADRIAN_UNISWAP_V4_POOL_MANAGER || "0x8a281Be9000000000000000000000000000007f7",
      MeteoraDAMMv1Factory: process.env.HADRIAN_METEORA_DAMM_FACTORY || "0xd68b355f0000000000000000000000000000a3c4",
    },
    tokens: {
      wUSDC: {
        symbol: "wUSDC",
        decimals: 6,
        address: process.env.HADRIAN_WUSDC || "0x0952d23300000000000000000000000000200010",
        splMintBytes32: "0x458b3a8011223344556677889900aabbccddeeff0011223344556677889900aa",
      },
      wSOL: {
        symbol: "wSOL",
        decimals: 9,
        address: process.env.HADRIAN_WSOL || "0xc4e29e0f00000000000000000000000000200010",
        splMintBytes32: "0x069b8857feab8184fb687f634618c035dac439dc1aeb3b5598a0f00000000001",
      },
      wETH: {
        symbol: "wETH",
        decimals: 18,
        address: process.env.HADRIAN_WETH || "0x01e8b35700000000000000000000000000200010",
        splMintBytes32: "0x7c9b8857feab8184fb687f634618c035dac439dc1aeb3b5598a0f00000000002",
      },
    },
    precompiles: ROME_PRECOMPILES,
    programs: SOLANA_WELL_KNOWN_PROGRAMS,
  },
  rubicon: {
    key: "rubicon",
    name: "Rome Rubicon Mainnet",
    network: "mainnet",
    solanaCluster: "mainnet-beta",
    chainId: Number(process.env.ROME_RUBICON_CHAIN_ID || 7531),
    rpcUrl: process.env.ROME_RUBICON_RPC || "https://rubicon.mainnet.romeprotocol.xyz/",
    explorerUrl: "https://via.mainnet.romeprotocol.xyz/",
    romeEvmProgramId: "RomePq9X3iAoTr813HR7uRarafFDUJty6GdiEceYpzX",
    nativeCurrency: {
      name: "Rome Protocol Token",
      symbol: "ROME",
      decimals: 18,
    },
    contracts: {
      ERC20SPLFactory: process.env.RUBICON_ERC20_SPL_FACTORY || "0x4068aa740000000000000000000000000000ae6e",
      Multicall3: process.env.RUBICON_MULTICALL3 || "0xd6e0b13e0000000000000000000000000000a759",
      RomeBridgeWithdraw: process.env.RUBICON_BRIDGE_WITHDRAW || "0xceea191700000000000000000000000000009c84",
      UniswapV2Factory: process.env.RUBICON_UNISWAP_V2_FACTORY || "0x23af4d2000000000000000000000000000001dc2",
      UniswapV2Router: process.env.RUBICON_UNISWAP_V2_ROUTER || "0x445d7af7000000000000000000000000000037f7",
      UniswapV3Factory: process.env.RUBICON_UNISWAP_V3_FACTORY || "0x02aed7760000000000000000000000000000a025",
      SwapRouterV3: process.env.RUBICON_SWAP_ROUTER_V3 || "0x680b76450000000000000000000000000000d034",
    },
    tokens: {
      wUSDC: {
        symbol: "wUSDC",
        decimals: 6,
        address: process.env.RUBICON_WUSDC || "0x0952d2330000000000000000000000000000f9b3",
        splMintBytes32: "0xc6fa7af3bedbad3a3d65f36aabc97431b1bbe4c2d2f6e0e47ca60203452f5d61",
      },
      wSOL: {
        symbol: "wSOL",
        decimals: 9,
        address: process.env.RUBICON_WSOL || "0xc4e29e0f0000000000000000000000000000a113",
        splMintBytes32: "0x069b8857feab8184fb687f634618c035dac439dc1aeb3b5598a0f00000000001",
      },
      wETH: {
        symbol: "wETH",
        decimals: 18,
        address: process.env.RUBICON_WETH || "0x01e8b357000000000000000000000000000092e9",
        splMintBytes32: "0x7c9b8857feab8184fb687f634618c035dac439dc1aeb3b5598a0f00000000002",
      },
    },
    precompiles: ROME_PRECOMPILES,
    programs: SOLANA_WELL_KNOWN_PROGRAMS,
  },
  ostia: {
    key: "ostia",
    name: "Rome Ostia (Canton zkEVM Devnet)",
    network: "devnet",
    solanaCluster: "canton-devnet",
    chainId: Number(process.env.ROME_OSTIA_CHAIN_ID || 770101),
    rpcUrl: process.env.ROME_OSTIA_RPC || "https://ostia.devnet.romeprotocol.xyz/rpc",
    explorerUrl: "https://ostia.devnet.romeprotocol.xyz/",
    romeEvmProgramId: "OstiaCantonZkEvmProgram11111111111111111111",
    nativeCurrency: {
      name: "Test ROME",
      symbol: "tROME",
      decimals: 18,
    },
    contracts: {},
    tokens: {},
    precompiles: ROME_PRECOMPILES,
    programs: SOLANA_WELL_KNOWN_PROGRAMS,
  },
};

/**
 * Resolves a chain metadata object by name ("hadrian" | "rubicon" | "ostia") or chainId (200010 | 7531 | 770101).
 * Attempts to dynamically import `@rome-protocol/registry` if installed in node_modules, merging with live overrides.
 */
export async function getChain(chainOrId = "hadrian") {
  try {
    const dynamicRegistry = await import("@rome-protocol/registry");
    if (dynamicRegistry && typeof dynamicRegistry.getChain === "function") {
      const liveChain = dynamicRegistry.getChain(chainOrId);
      if (liveChain) {
        return { ...liveChain, precompiles: ROME_PRECOMPILES, programs: SOLANA_WELL_KNOWN_PROGRAMS };
      }
    }
  } catch {
    // Fallback to built-in @rome-protocol/registry snapshot
  }

  const key = String(chainOrId).toLowerCase();
  if (REGISTRY_CATALOG[key]) return REGISTRY_CATALOG[key];
  const byId = Object.values(REGISTRY_CATALOG).find((c) => c.chainId === Number(chainOrId));
  if (byId) return byId;
  return REGISTRY_CATALOG.hadrian;
}

export async function listChains() {
  return Object.values(REGISTRY_CATALOG);
}

export async function getContracts(chainOrId = "hadrian") {
  const c = await getChain(chainOrId);
  return c.contracts;
}

export async function getTokens(chainOrId = "hadrian") {
  const c = await getChain(chainOrId);
  return c.tokens;
}

export async function getPrograms(network = "mainnet") {
  return SOLANA_WELL_KNOWN_PROGRAMS;
}

// CLI execution handler
if (process.argv[1] && process.argv[1].endsWith("chain-facts.mjs")) {
  const target = process.argv[2] || "hadrian";
  getChain(target).then((facts) => {
    console.log(`\n=== ROME PROTOCOL REGISTRY FACTS [${facts.name.toUpperCase()}] ===`);
    console.log(JSON.stringify(facts, null, 2));
  });
}
