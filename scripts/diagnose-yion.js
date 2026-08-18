require("dotenv").config();

const Web3 = require("web3");
const YION_ARTIFACT = require("../build/contracts/YION.json");
const ROUTER = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1";

const ERC20_ABI = [
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }],
    name: "allowance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
];

const PAIR_ABI = [
  {
    inputs: [],
    name: "token0",
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "token1",
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getReserves",
    outputs: [
      { name: "reserve0", type: "uint112" },
      { name: "reserve1", type: "uint112" },
      { name: "blockTimestampLast", type: "uint32" },
    ],
    stateMutability: "view",
    type: "function",
  },
];

async function optionalCall(call) {
  try {
    return await call();
  } catch (_) {
    return "CALL_REVERTED_NOT_SUPPORTED";
  }
}

async function main() {
  const required = ["TESTNET_RPC_URL", "YION_ADDRESS", "YION_USDT_ADDRESS"];
  for (const name of required) {
    if (!process.env[name]) throw new Error(`${name} is required`);
  }

  const web3 = new Web3(process.env.TESTNET_RPC_URL);
  const yion = new web3.eth.Contract(YION_ARTIFACT.abi, process.env.YION_ADDRESS);
  const usdt = new web3.eth.Contract(ERC20_ABI, process.env.YION_USDT_ADDRESS);
  const account = process.env.TRADER_ADDRESS || process.env.DEPLOYER_ADDRESS;

  const result = {
    chainId: Number(await web3.eth.getChainId()),
    yion: {
      address: process.env.YION_ADDRESS,
      codeBytes: ((await web3.eth.getCode(process.env.YION_ADDRESS)).length - 2) / 2,
      configuredPair: await yion.methods.liquidityPair().call(),
      restrictionActive: await yion.methods.restrictionActive().call(),
      restrictedUntil: (await yion.methods.restrictedUntil().call()).toString(),
      feeRecipient: await optionalCall(() => yion.methods.FEE_RECIPIENT().call()),
      feeBps: await optionalCall(() => yion.methods.TRADE_FEE_BPS().call()),
    },
  };

  if (process.env.YION_USDT_PAIR) {
    const pair = new web3.eth.Contract(PAIR_ABI, process.env.YION_USDT_PAIR);
    const reserves = await pair.methods.getReserves().call();
    result.pair = {
      address: process.env.YION_USDT_PAIR,
      token0: await pair.methods.token0().call(),
      token1: await pair.methods.token1().call(),
      reserve0: reserves.reserve0.toString(),
      reserve1: reserves.reserve1.toString(),
    };
  }

  if (account) {
    result.trader = {
      address: account,
      yionBalance: (await yion.methods.balanceOf(account).call()).toString(),
      usdtBalance: (await usdt.methods.balanceOf(account).call()).toString(),
      usdtAllowanceToYion: (await usdt.methods.allowance(account, process.env.YION_ADDRESS).call()).toString(),
      yionAllowanceToRouter: (await yion.methods.allowance(account, ROUTER).call()).toString(),
      usdtAllowanceToRouter: (await usdt.methods.allowance(account, ROUTER).call()).toString(),
    };
  }

  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
