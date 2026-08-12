require("dotenv").config();

const path = require("path");
const ganache = require("ganache");
const HDWalletProvider = require("@truffle/hdwallet-provider");

let testProvider;

module.exports = {
  networks: {
    // `npm test` uses this isolated in-memory chain. Keeping one provider
    // instance is important because Truffle asks for it more than once.
    test: {
      provider: () => {
        if (!testProvider) {
          testProvider = ganache.provider({
            chain: { chainId: 1337, networkId: 1337 },
            logging: { quiet: true },
            wallet: { totalAccounts: 20, defaultBalance: 1_000 },
          });
        }
        return testProvider;
      },
      network_id: 1337,
    },

    // Start it with `npm run ganache`, then deploy with `npm run migrate:local`.
    development: {
      host: process.env.RPC_HOST || "127.0.0.1",
      port: Number(process.env.RPC_PORT || 8545),
      network_id: process.env.NETWORK_ID || "*",
    },

    // Truffle Dashboard signs deployments through the connected wallet.
    dashboard: {},

    bscTestnet: {
      provider: () => {
        if (!process.env.TESTNET_RPC_URL) {
          throw new Error("TESTNET_RPC_URL is required for bscTestnet");
        }
        if (!process.env.DEPLOYER_PRIVATE_KEY) {
          throw new Error("DEPLOYER_PRIVATE_KEY is required for bscTestnet");
        }
        return new HDWalletProvider({
          privateKeys: [process.env.DEPLOYER_PRIVATE_KEY.replace(/^0x/, "")],
          providerOrUrl: process.env.TESTNET_RPC_URL,
        });
      },
      network_id: 97,
      chain_id: 97,
      confirmations: 2,
      timeoutBlocks: 200,
      skipDryRun: true,
    },
  },

  mocha: {
    timeout: 100_000,
  },

  compilers: {
    solc: {
      // Pin the npm-installed compiler so builds do not depend on solc-bin.
      version: path.resolve(__dirname, "node_modules/solc/soljson.js"),
      settings: {
        optimizer: { enabled: true, runs: 200 },
      },
    },
  },
};
