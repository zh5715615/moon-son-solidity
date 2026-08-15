const YION = artifacts.require("YION");
const GameRewardPool = artifacts.require("GameRewardPool");
const Bullfigthing = artifacts.require("Bullfigthing");
const GoldenFlower = artifacts.require("GoldenFlower");
const Landlords = artifacts.require("Landlords");
const {
  recordDeployment,
  recordLiquidity,
  recordLiquidityActivation,
} = require("./lib/record-deployment");

const BSC_TESTNET_USDT = "0x5B32Cc7d18643073BDB15dAfafC5C35E736c91a5";
const BSC_TESTNET_V2_ROUTER = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1";
const USDT_LIQUIDITY = "10000";
const MIN_NATIVE_BALANCE_WEI = "200000000000000000";

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

async function recordContract(contract, instance, deployer, constructorArguments) {
  console.log(`${contract} deployed: ${instance.address}`);
  console.log(`${contract} transaction: ${instance.transactionHash}`);
  await recordDeployment({
    web3,
    contract,
    instance,
    deployer,
    constructorArguments,
  });
}

module.exports = async function (callback) {
  try {
    const chainId = Number(await web3.eth.getChainId());
    if (chainId !== 97) {
      throw new Error(`One-click YION deployment only supports BSC Testnet (97), got ${chainId}`);
    }

    const [deployer] = await web3.eth.getAccounts();
    const dealer = process.env.DEALER_ADDRESS || deployer;
    const bullOwner = process.env.BULL_OWNER_ADDRESS || deployer;
    const nativeBalance = web3.utils.toBN(await web3.eth.getBalance(deployer));
    if (nativeBalance.lt(web3.utils.toBN(MIN_NATIVE_BALANCE_WEI))) {
      throw new Error(
        `Insufficient testnet BNB for the full deployment: need at least 0.2, ` +
        `have ${web3.utils.fromWei(nativeBalance, "ether")}`
      );
    }

    const usdt = new web3.eth.Contract(ERC20_ABI, BSC_TESTNET_USDT);
    const usdtDecimals = Number(await usdt.methods.decimals().call());
    const usdtUnit = web3.utils.toBN(10).pow(web3.utils.toBN(usdtDecimals));
    const usdtAmount = web3.utils.toBN(USDT_LIQUIDITY).mul(usdtUnit);
    const usdtBalance = web3.utils.toBN(await usdt.methods.balanceOf(deployer).call());
    if (usdtBalance.lt(usdtAmount)) {
      throw new Error(
        `Insufficient testnet USDT: need 10000, have ${usdtBalance.div(usdtUnit).toString()}`
      );
    }

    console.log("YION ecosystem one-click deployment preflight passed");
    console.log(`Deployer: ${deployer}`);
    console.log(`Dealer: ${dealer}`);
    console.log(`Bull owner: ${bullOwner}`);
    console.log(`Native balance: ${web3.utils.fromWei(nativeBalance, "ether")} BNB`);
    console.log(`USDT balance (base units): ${usdtBalance.toString()}`);
    if (process.env.YION_ECOSYSTEM_PREFLIGHT_ONLY === "true") {
      console.log("Preflight-only mode; no transaction submitted");
      return callback();
    }

    // 1. Deploy the fixed-supply YION contract. Trading remains closed.
    console.log("\n[1/5] Deploying YION");
    const yion = await YION.new(BSC_TESTNET_USDT, BSC_TESTNET_V2_ROUTER, { from: deployer });
    const yionAmount = web3.utils.toBN(await yion.totalSupply());
    await recordContract("YION", yion, deployer, {
      usdt: BSC_TESTNET_USDT,
      router: BSC_TESTNET_V2_ROUTER,
    });

    // 2. Create and seed the YION/USDT PancakeSwap V2 pool.
    console.log("\n[2/5] Creating YION/USDT liquidity pool");
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
      throw new Error("PancakeSwap YION/USDT pair was not created");
    }
    const lpToken = new web3.eth.Contract(ERC20_ABI, pair);
    const lpBalance = await lpToken.methods.balanceOf(deployer).call();
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
    });
    console.log(`YION/USDT pair: ${pair}`);
    console.log(`Liquidity transaction: ${liquidityReceipt.transactionHash}`);

    // 3. Deploy a reward pool that is permanently bound to this YION.
    console.log("\n[3/5] Deploying GameRewardPool with YION");
    const rewardPool = await GameRewardPool.new(yion.address, { from: deployer });
    await recordContract("GameRewardPool", rewardPool, deployer, { token: yion.address });

    // 4. Deploy all games with the new YION and reward pool.
    console.log("\n[4/5] Deploying Bullfigthing, GoldenFlower and Landlords with YION");
    const bullfigthing = await Bullfigthing.new(bullOwner, rewardPool.address, yion.address, { from: deployer });
    await recordContract("Bullfigthing", bullfigthing, deployer, {
      beneficiary: bullOwner,
      rewardPool: rewardPool.address,
      token: yion.address,
    });

    const goldenFlower = await GoldenFlower.new(yion.address, dealer, rewardPool.address, { from: deployer });
    await recordContract("GoldenFlower", goldenFlower, deployer, {
      token: yion.address,
      dealer,
      rewardPool: rewardPool.address,
    });

    const landlords = await Landlords.new(yion.address, dealer, rewardPool.address, { from: deployer });
    await recordContract("Landlords", landlords, deployer, {
      token: yion.address,
      dealer,
      rewardPool: rewardPool.address,
    });

    // 5. Open trading only after every ecosystem contract exists.
    console.log("\n[5/5] Activating YION trading and starting the 30-minute restriction");
    const activationReceipt = await yion.activateTrading(pair, { from: deployer });
    const restrictedUntil = (await yion.restrictedUntil()).toString();
    await recordLiquidityActivation({
      web3,
      liquidityTransactionHash: liquidityReceipt.transactionHash,
      activationTransactionHash: activationReceipt.tx,
      restrictedUntil,
    });

    console.log("\nYION ecosystem deployment complete");
    console.log(JSON.stringify({
      yion: yion.address,
      pair,
      rewardPool: rewardPool.address,
      bullfigthing: bullfigthing.address,
      goldenFlower: goldenFlower.address,
      landlords: landlords.address,
      dealer,
      bullOwner,
      lpHolder: deployer,
      activationTransaction: activationReceipt.tx,
      restrictedUntil,
    }, null, 2));
    callback();
  } catch (error) {
    callback(error);
  }
};
