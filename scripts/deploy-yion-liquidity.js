const YION = artifacts.require("YION");
const { recordDeployment, recordLiquidity } = require("./lib/record-deployment");

const BSC_TESTNET_USDT = "0x5B32Cc7d18643073BDB15dAfafC5C35E736c91a5";
const BSC_TESTNET_V2_ROUTER = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1";
const YION_SUPPLY = "100000000";
const USDT_LIQUIDITY = "10000";

const ERC20_ABI = [
  { constant: true, inputs: [{ name: "account", type: "address" }], name: "balanceOf", outputs: [{ name: "", type: "uint256" }], type: "function" },
  { constant: true, inputs: [], name: "decimals", outputs: [{ name: "", type: "uint8" }], type: "function" },
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

module.exports = async function (callback) {
  try {
    const chainId = Number(await web3.eth.getChainId());
    if (chainId !== 97) throw new Error(`YION liquidity script only supports BSC Testnet (97), got ${chainId}`);

    const [deployer] = await web3.eth.getAccounts();
    const usdt = new web3.eth.Contract(ERC20_ABI, BSC_TESTNET_USDT);
    const usdtDecimals = Number(await usdt.methods.decimals().call());
    const usdtLiquidity = web3.utils.toBN(USDT_LIQUIDITY);
    const usdtAmount = usdtLiquidity.mul(web3.utils.toBN(10).pow(web3.utils.toBN(usdtDecimals)));
    const usdtBalance = web3.utils.toBN(await usdt.methods.balanceOf(deployer).call());
    if (usdtBalance.lt(usdtAmount)) {
      throw new Error(
        `Insufficient testnet USDT: need ${USDT_LIQUIDITY}, ` +
        `have ${usdtBalance.div(web3.utils.toBN(10).pow(web3.utils.toBN(usdtDecimals))).toString()}`
      );
    }

    console.log(`Deployer: ${deployer}`);
    console.log(`USDT decimals: ${usdtDecimals}`);
    console.log(`Deployer USDT balance (base units): ${usdtBalance.toString()}`);
    console.log(`Creating initial pool with 100,000,000 YION and 10,000 USDT`);
    if (process.env.YION_PREFLIGHT_ONLY === "true") {
      console.log("YION preflight passed; no transaction submitted");
      return callback();
    }

    const yion = await YION.new(BSC_TESTNET_USDT, BSC_TESTNET_V2_ROUTER, { from: deployer });
    const yionAmount = web3.utils.toBN(await yion.totalSupply());
    console.log(`YION deployed: ${yion.address}`);
    console.log(`YION transaction: ${yion.transactionHash}`);
    await recordDeployment({
      web3,
      contract: "YION",
      instance: yion,
      deployer,
      constructorArguments: {
        usdt: BSC_TESTNET_USDT,
        router: BSC_TESTNET_V2_ROUTER,
      },
    });

    const router = new web3.eth.Contract(ROUTER_ABI, BSC_TESTNET_V2_ROUTER);
    const factoryAddress = await router.methods.factory().call();
    const factory = new web3.eth.Contract(FACTORY_ABI, factoryAddress);

    await yion.approve(BSC_TESTNET_V2_ROUTER, yionAmount, { from: deployer });
    await usdt.methods.approve(BSC_TESTNET_V2_ROUTER, usdtAmount).send({ from: deployer });

    const latestBlock = await web3.eth.getBlock("latest");
    const deadline = Number(latestBlock.timestamp) + 20 * 60;
    const liquidityReceipt = await router.methods.addLiquidity(
      yion.address,
      BSC_TESTNET_USDT,
      yionAmount.toString(),
      usdtAmount.toString(),
      yionAmount.toString(),
      usdtAmount.toString(),
      deployer,
      deadline
    ).send({ from: deployer });

    const pair = await factory.methods.getPair(yion.address, BSC_TESTNET_USDT).call();
    if (pair === "0x0000000000000000000000000000000000000000") {
      throw new Error("PancakeSwap pair was not created");
    }
    const lpToken = new web3.eth.Contract(ERC20_ABI, pair);
    const lpBalance = await lpToken.methods.balanceOf(deployer).call();
    const activationReceipt = await yion.activateTrading(pair, { from: deployer });
    const restrictedUntil = (await yion.restrictedUntil()).toString();

    await recordLiquidity({
      web3,
      pair,
      token: yion.address,
      quoteToken: BSC_TESTNET_USDT,
      router: BSC_TESTNET_V2_ROUTER,
      provider: deployer,
      transactionHash: liquidityReceipt.transactionHash,
      tokenAmount: yionAmount.toString(),
      quoteTokenAmount: usdtAmount.toString(),
      lpTokens: lpBalance.toString(),
      initialPrice: "1 USDT = 10000 YION",
      activationTransactionHash: activationReceipt.tx,
      restrictedUntil,
    });

    console.log(`YION/USDT pair: ${pair}`);
    console.log(`Liquidity transaction: ${liquidityReceipt.transactionHash}`);
    console.log(`Trading activation transaction: ${activationReceipt.tx}`);
    console.log(`Whitelist restriction ends at: ${restrictedUntil}`);
    console.log(`LP tokens held by deployer: ${lpBalance}`);
    callback();
  } catch (error) {
    callback(error);
  }
};
