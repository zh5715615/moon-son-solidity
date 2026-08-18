const fs = require("fs");
const path = require("path");
const YION = artifacts.require("YION");
const {
  recordLiquidity,
  recordLiquidityActivation,
} = require("./lib/record-deployment");

const USDT = "0x5B32Cc7d18643073BDB15dAfafC5C35E736c91a5";
const ROUTER = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1";
const USDT_AMOUNT = "10000000000000000000000";

const ERC20_ABI = [
  { constant: true, inputs: [{ name: "account", type: "address" }], name: "balanceOf", outputs: [{ name: "", type: "uint256" }], type: "function" },
  { constant: false, inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], name: "approve", outputs: [{ name: "", type: "bool" }], type: "function" },
];

const ROUTER_ABI = [
  { constant: true, inputs: [], name: "factory", outputs: [{ name: "", type: "address" }], type: "function" },
  {
    constant: false,
    inputs: [
      { name: "tokenA", type: "address" },
      { name: "tokenB", type: "address" },
      { name: "amountADesired", type: "uint256" },
      { name: "amountBDesired", type: "uint256" },
      { name: "amountAMin", type: "uint256" },
      { name: "amountBMin", type: "uint256" },
      { name: "to", type: "address" },
      { name: "deadline", type: "uint256" },
    ],
    name: "addLiquidity",
    outputs: [
      { name: "amountA", type: "uint256" },
      { name: "amountB", type: "uint256" },
      { name: "liquidity", type: "uint256" },
    ],
    type: "function",
  },
];

const FACTORY_ABI = [
  { constant: true, inputs: [{ name: "tokenA", type: "address" }, { name: "tokenB", type: "address" }], name: "getPair", outputs: [{ name: "pair", type: "address" }], type: "function" },
];

function findLiquidityTransaction(token) {
  const registryPath = path.resolve(__dirname, "..", "deployments", "bsc-testnet-97.json");
  const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
  const item = [...(registry.liquidityPools || [])]
    .reverse()
    .find((pool) => pool.token.toLowerCase() === token.toLowerCase());
  if (!item) throw new Error(`No recorded liquidity found for ${token}`);
  return item.transactionHash;
}

module.exports = async function (callback) {
  try {
    if (Number(await web3.eth.getChainId()) !== 97) throw new Error("BSC Testnet only");
    if (!process.env.YION_ADDRESS) throw new Error("YION_ADDRESS is required");
    if (!process.env.YION_LIQUIDITY_STEP) throw new Error("YION_LIQUIDITY_STEP is required");

    const [deployer] = await web3.eth.getAccounts();
    const yion = await YION.at(process.env.YION_ADDRESS);
    const usdt = new web3.eth.Contract(ERC20_ABI, USDT);
    const router = new web3.eth.Contract(ROUTER_ABI, ROUTER);
    const factory = new web3.eth.Contract(FACTORY_ABI, await router.methods.factory().call());
    const yionAmount = (await yion.totalSupply()).toString();
    const step = process.env.YION_LIQUIDITY_STEP;

    if (step === "approve") {
      const yionApproval = await yion.approve(ROUTER, yionAmount, { from: deployer });
      console.log(`YION approval: ${yionApproval.tx}`);
      const usdtApproval = await usdt.methods.approve(ROUTER, USDT_AMOUNT).send({ from: deployer });
      console.log(`USDT approval: ${usdtApproval.transactionHash}`);
      return callback();
    }

    if (step === "liquidity") {
      const latestBlock = await web3.eth.getBlock("latest");
      const receipt = await router.methods.addLiquidity(
        yion.address,
        USDT,
        yionAmount,
        USDT_AMOUNT,
        yionAmount,
        USDT_AMOUNT,
        deployer,
        Number(latestBlock.timestamp) + 20 * 60
      ).send({ from: deployer });
      const pair = await factory.methods.getPair(yion.address, USDT).call();
      const lp = new web3.eth.Contract(ERC20_ABI, pair);
      const lpBalance = await lp.methods.balanceOf(deployer).call();
      await recordLiquidity({
        web3,
        pair,
        token: yion.address,
        quoteToken: USDT,
        router: ROUTER,
        provider: deployer,
        transactionHash: receipt.transactionHash,
        tokenAmount: yionAmount,
        quoteTokenAmount: USDT_AMOUNT,
        lpTokens: lpBalance.toString(),
        initialPrice: "1 USDT = 10000 YION",
      });
      console.log(`Pair: ${pair}`);
      console.log(`Liquidity transaction: ${receipt.transactionHash}`);
      return callback();
    }

    if (step === "activate") {
      const pair = await factory.methods.getPair(yion.address, USDT).call();
      const receipt = await yion.activateTrading(pair, { from: deployer });
      const restrictedUntil = (await yion.restrictedUntil()).toString();
      await recordLiquidityActivation({
        web3,
        liquidityTransactionHash: findLiquidityTransaction(yion.address),
        activationTransactionHash: receipt.tx,
        restrictedUntil,
      });
      console.log(`Pair: ${pair}`);
      console.log(`Activation transaction: ${receipt.tx}`);
      console.log(`Restricted until: ${restrictedUntil}`);
      return callback();
    }

    throw new Error(`Unsupported YION_LIQUIDITY_STEP: ${step}`);
  } catch (error) {
    callback(error);
  }
};
