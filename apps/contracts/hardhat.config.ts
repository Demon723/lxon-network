import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "dotenv/config";
import { HttpNetworkConfig, Provider } from "hardhat/types";

function createLXONProvider(url: string, chainId: number): HttpNetworkConfig {
  return {
    url,
    chainId,
    timeout: 300000,
    httpHeaders: {},
  };
}

// Custom provider that mocks net_version for LXON RPC
function createLXONCustomProvider(url: string, chainId: number): Provider {
  const { ethers } = require("ethers");
  const provider = new ethers.JsonRpcProvider(url);
  
  const originalSend = provider.send.bind(provider);
  provider.send = async (method: string, params: any[]) => {
    if (method === "net_version") {
      return chainId.toString();
    }
    return originalSend(method, params);
  };
  
  return provider;
}

const lxonUrl = process.env.LXON_RPC_URL || "http://16.170.33.13:8546";
const lxonMainnetUrl = process.env.LXON_MAINNET_RPC_URL || "http://16.170.33.13:8546";
const privateKey = process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : [];

const lxonNetwork: HttpNetworkConfig = {
  url: lxonUrl,
  chainId: 724,
  accounts: privateKey,
  timeout: 300000,
  httpHeaders: {},
};

const lxonMainnetNetwork: HttpNetworkConfig = {
  url: lxonMainnetUrl,
  chainId: 724,
  accounts: privateKey,
  timeout: 300000,
};

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          evmVersion: "london", // Pre-Shanghai, compatible with Geth v1.10.26
          viaIR: false,
        },
      },
      {
        version: "0.8.24",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          evmVersion: "london",
          viaIR: false,
        },
      },
      {
        version: "0.8.26",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          evmVersion: "london",
          viaIR: false,
        },
      },
    ],
  },

  networks: {
    hardhat: {
      chainId: 724,
      forking: process.env.FORKING === "true"
        ? {
            url: process.env.MAINNET_RPC_URL || "",
          }
        : undefined,
    },

    localhost: {
      url: "http://127.0.0.1:8545",
      // Use Hardhat default mnemonic accounts
      accounts: {
        mnemonic: "test test test test test test test test test test test junk",
        path: "m/44'/60'/0'/0",
        initialIndex: 0,
        count: 20,
      },
    },

    // Ethereum Testnets
    sepolia: {
      url:
        process.env.SEPOLIA_RPC_URL ||
        "https://ethereum-sepolia-rpc.publicnode.com",
      accounts: process.env.PRIVATE_KEY 
        ? [process.env.PRIVATE_KEY]
        : (process.env.DEPLOYER_PRIVATE_KEY 
          ? [process.env.DEPLOYER_PRIVATE_KEY]
          : []),
      chainId: 11155111,
      timeout: 120000,
    },

    holesky: {
      url: process.env.HOLESKY_RPC_URL || "https://ethereum-holesky-rpc.publicnode.com",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : (process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : []),
      chainId: 17000,
    },

    // Ethereum Mainnet
    mainnet: {
      url: process.env.MAINNET_RPC_URL || "",
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : [],
      chainId: 1,
    },

    // Layer 2s (for future x402 integration)
    base: {
      url: process.env.BASE_RPC_URL || "https://mainnet.base.org",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 8453,
    },

    baseSepolia: {
      url: process.env.BASE_SEPOLIA_RPC_URL || "https://sepolia.base.org",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 84532,
    },

    arbitrum: {
      url: process.env.ARBITRUM_RPC_URL || "https://arb1.arbitrum.io/rpc",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 42161,
    },

    polygon: {
      url: process.env.POLYGON_RPC_URL || "https://polygon.drpc.org",
      accounts: process.env.PRIVATE_KEY 
        ? [process.env.PRIVATE_KEY]
        : (process.env.DEPLOYER_PRIVATE_KEY 
          ? [process.env.DEPLOYER_PRIVATE_KEY]
          : []),
      chainId: 137,
      timeout: 120000, // 2 minutes for network congestion
    },

    // LXON Native Networks
    lxon: lxonNetwork,

    lxonMainnet: lxonMainnetNetwork,
    
    // Use LXON network for liquidity deployment
    lxonDeploy: {
      url: process.env.LXON_RPC_URL || "http://13.53.138.132:8546",
      chainId: 724,
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : {
        mnemonic: "test test test test test test test test test test test junk",
        path: "m/44'/60'/0'/0",
        initialIndex: 0,
        count: 20,
      },
    },
  },

  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || "",
      sepolia: process.env.ETHERSCAN_API_KEY || "",
      holesky: process.env.ETHERSCAN_API_KEY || "",
      base: process.env.BASESCAN_API_KEY || "",
      baseSepolia: process.env.BASESCAN_API_KEY || "",
      arbitrumOne: process.env.ARBISCAN_API_KEY || "",
      polygon: process.env.POLYGONSCAN_API_KEY || "",
      lxon: process.env.LXON_EXPLORER_API_KEY || "",
    },
    customChains: [
      {
        network: "lxon",
        chainId: 724,
        urls: {
          apiURL: "https://explorer.lxon.in/api",
          browserURL: "https://explorer.lxon.in",
        },
      },
    ],
  },

  gasReporter: {
    enabled: process.env.REPORT_GAS === "true",
    currency: "USD",
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    outputFile: "gas-report.txt",
    noColors: true,
  },

  sourcify: {
    enabled: process.env.SOURCIFY_ENABLED === "true",
  },

  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },

  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
    alwaysGenerateOverloads: true,
  },

  mocha: {
    timeout: 40000,
  },
};

export default config;
