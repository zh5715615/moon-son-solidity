const YION = artifacts.require("YION");
const GameRewardPool = artifacts.require("GameRewardPool");
const Bullfigthing = artifacts.require("Bullfigthing");
const GoldenFlower = artifacts.require("GoldenFlower");
const Landlords = artifacts.require("Landlords");
const fs = require("fs");
const path = require("path");
const readline = require("readline");
const {
  recordDeployment,
  recordLiquidity,
  recordLiquidityActivation,
} = require("./lib/record-deployment");

const BSC_TESTNET_USDT = "0x5B32Cc7d18643073BDB15dAfafC5C35E736c91a5";
const BSC_TESTNET_V2_ROUTER = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1";
const USDT_LIQUIDITY = "10000";
const MIN_NATIVE_BALANCE_WEI = "200000000000000000";
const REGISTRY_PATH = path.resolve(__dirname, "..", "deployments", "bsc-testnet-97.json");

const DEPLOYMENT_CHOICES = [
  { key: "yion", contract: "YION", label: "YION", env: "DEPLOY_YION" },
  { key: "rewardPool", contract: "GameRewardPool", label: "奖励合约 GameRewardPool", env: "DEPLOY_REWARD_POOL" },
  { key: "bullfigthing", contract: "Bullfigthing", label: "斗牛合约 Bullfigthing", env: "DEPLOY_BULLFIGTHING" },
  { key: "goldenFlower", contract: "GoldenFlower", label: "炸金花合约 GoldenFlower", env: "DEPLOY_GOLDEN_FLOWER" },
  { key: "landlords", contract: "Landlords", label: "斗地主合约 Landlords", env: "DEPLOY_LANDLORDS" },
];

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

function readRegistry() {
  return JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
}

function latestSuccessfulDeployment(registry, contract) {
  return [...registry.deployments]
    .reverse()
    .find((item) => item.contract === contract && item.status === "success");
}

function latestLiquidityForToken(registry, tokenAddress) {
  return [...(registry.liquidityPools || [])]
    .reverse()
    .find((item) => item.status === "success" &&
      item.token.toLowerCase() === tokenAddress.toLowerCase());
}

function parseBooleanChoice(value, name) {
  if (value === undefined) return undefined;
  const normalized = value.trim().toLowerCase();
  if (["1", "true", "yes", "y"].includes(normalized)) return true;
  if (["0", "false", "no", "n"].includes(normalized)) return false;
  throw new Error(`${name} must be true/false, yes/no or 1/0`);
}

function ask(rl, question) {
  return new Promise((resolve) => rl.question(question, resolve));
}

async function askDeploymentChoice(rl, choice, previous, index) {
  const configured = parseBooleanChoice(process.env[choice.env], choice.env);
  if (configured !== undefined) {
    console.log(
      `[${index + 1}/5] ${choice.label}: ${configured ? "部署新合约" : `复用 ${previous ? previous.address : "（无历史地址）"}`} ` +
      `(${choice.env}=${process.env[choice.env]})`
    );
    return configured;
  }

  const previousText = previous ? `，输入 n 复用 ${previous.address}` : "，当前没有历史部署地址";
  while (true) {
    const answer = (await ask(
      rl,
      `[${index + 1}/5] 是否部署新的${choice.label}？输入 y 部署${previousText} [y/N]: `
    )).trim().toLowerCase();
    if (["y", "yes"].includes(answer)) return true;
    if (["", "n", "no"].includes(answer)) {
      if (!previous) {
        console.log(`${choice.label}没有可复用的成功部署记录，请选择 y。`);
        continue;
      }
      return false;
    }
    console.log("请输入 y 或 n。");
  }
}

function constructorAddress(record, ...keys) {
  const args = record && record.constructorArguments;
  if (!args) return undefined;
  for (const key of keys) {
    if (args[key]) return args[key];
  }
  return undefined;
}

function sameAddress(left, right) {
  return Boolean(left && right && left.toLowerCase() === right.toLowerCase());
}

function validateReuseDependencies(plan, previous) {
  if (plan.yion && !plan.rewardPool) {
    throw new Error("不能部署新 YION 同时复用旧奖励池；奖励池永久绑定旧 YION。请选择同时部署奖励池。");
  }
  if (plan.yion && (!plan.bullfigthing || !plan.goldenFlower || !plan.landlords)) {
    throw new Error("部署新 YION 时三个游戏都必须重新部署，否则游戏仍会绑定旧 YION。");
  }
  if (plan.rewardPool && (!plan.bullfigthing || !plan.goldenFlower || !plan.landlords)) {
    throw new Error("部署新奖励池时三个游戏都必须重新部署，否则游戏仍会绑定旧奖励池。");
  }

  if (plan.yion) return;

  const selectedYion = previous.yion.address;
  const selectedReward = plan.rewardPool ? undefined : previous.rewardPool.address;
  if (!plan.rewardPool) {
    const rewardYion = constructorAddress(previous.rewardPool, "yion", "token");
    if (!sameAddress(rewardYion, selectedYion)) {
      throw new Error(`上次奖励池绑定 ${rewardYion || "未知 YION"}，与上次 YION ${selectedYion} 不匹配。`);
    }
  }

  for (const choice of DEPLOYMENT_CHOICES.slice(2)) {
    if (plan[choice.key]) continue;
    const record = previous[choice.key];
    const gameYion = constructorAddress(record, "yion", "token");
    const gameReward = constructorAddress(record, "rewardPool");
    if (!sameAddress(gameYion, selectedYion) || !sameAddress(gameReward, selectedReward)) {
      throw new Error(
        `${choice.label}的上次部署依赖不匹配：YION=${gameYion || "未知"}，` +
        `rewardPool=${gameReward || "未知"}。请重新部署该游戏。`
      );
    }
  }
}

async function requireContractCode(address, label) {
  const code = await web3.eth.getCode(address);
  if (!code || code === "0x" || code === "0x0") {
    throw new Error(`${label}复用地址没有链上代码: ${address}`);
  }
}

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
    const registry = readRegistry();
    const previous = Object.fromEntries(
      DEPLOYMENT_CHOICES.map((choice) => [
        choice.key,
        latestSuccessfulDeployment(registry, choice.contract),
      ])
    );
    const needsPrompt = DEPLOYMENT_CHOICES.some((choice) => process.env[choice.env] === undefined);
    const rl = needsPrompt
      ? readline.createInterface({ input: process.stdin, output: process.stdout })
      : undefined;
    const plan = {};
    try {
      console.log("\nYION 生态部署向导（默认 n：复用上次部署）\n");
      for (let i = 0; i < DEPLOYMENT_CHOICES.length; i++) {
        const choice = DEPLOYMENT_CHOICES[i];
        plan[choice.key] = await askDeploymentChoice(rl, choice, previous[choice.key], i);
      }
    } finally {
      if (rl) rl.close();
    }

    for (const choice of DEPLOYMENT_CHOICES) {
      if (!plan[choice.key] && !previous[choice.key]) {
        throw new Error(`${choice.label}没有可复用的成功部署记录`);
      }
    }
    validateReuseDependencies(plan, previous);

    const chainId = Number(await web3.eth.getChainId());
    if (chainId !== 97) {
      throw new Error(`YION ecosystem deployment only supports BSC Testnet (97), got ${chainId}`);
    }

    const [deployer] = await web3.eth.getAccounts();
    const dealer = process.env.DEALER_ADDRESS || deployer;
    const bullOwner = process.env.BULL_OWNER_ADDRESS || deployer;
    const deploymentCount = Object.values(plan).filter(Boolean).length;
    const nativeBalance = web3.utils.toBN(await web3.eth.getBalance(deployer));
    const partialNativeRequirement = web3.utils.toBN("40000000000000000").muln(deploymentCount);
    const nativeRequirement = plan.yion
      ? web3.utils.toBN(MIN_NATIVE_BALANCE_WEI)
      : partialNativeRequirement;
    if (deploymentCount > 0 && nativeBalance.lt(nativeRequirement)) {
      throw new Error(
        `Insufficient testnet BNB: need at least ${web3.utils.fromWei(nativeRequirement, "ether")}, ` +
        `have ${web3.utils.fromWei(nativeBalance, "ether")}`
      );
    }

    let usdt;
    let usdtAmount;
    let usdtBalance;
    if (plan.yion) {
      usdt = new web3.eth.Contract(ERC20_ABI, BSC_TESTNET_USDT);
      const usdtDecimals = Number(await usdt.methods.decimals().call());
      const usdtUnit = web3.utils.toBN(10).pow(web3.utils.toBN(usdtDecimals));
      usdtAmount = web3.utils.toBN(USDT_LIQUIDITY).mul(usdtUnit);
      usdtBalance = web3.utils.toBN(await usdt.methods.balanceOf(deployer).call());
      if (usdtBalance.lt(usdtAmount)) {
        throw new Error(
          `Insufficient testnet USDT: need 10000, have ${usdtBalance.div(usdtUnit).toString()}`
        );
      }
    }

    for (const choice of DEPLOYMENT_CHOICES) {
      if (!plan[choice.key]) {
        await requireContractCode(previous[choice.key].address, choice.label);
      }
    }

    const reusedLiquidity = plan.yion
      ? undefined
      : latestLiquidityForToken(registry, previous.yion.address);
    if (!plan.yion && !reusedLiquidity) {
      throw new Error(`找不到上次 YION ${previous.yion.address} 对应的流动性池记录`);
    }
    if (reusedLiquidity) {
      if (!reusedLiquidity.activationTransactionHash) {
        throw new Error(`上次 YION ${previous.yion.address} 的流动性池尚未登记交易激活`);
      }
      await requireContractCode(reusedLiquidity.pair, "YION/USDT Pair");
      const reusedYion = await YION.at(previous.yion.address);
      const activePair = await reusedYion.liquidityPair();
      if (!sameAddress(activePair, reusedLiquidity.pair)) {
        throw new Error(
          `上次 YION 链上激活 Pair ${activePair} 与部署登记 ${reusedLiquidity.pair} 不一致`
        );
      }
    }

    console.log("\n部署计划预检通过");
    console.log(`Deployer: ${deployer}`);
    console.log(`Dealer: ${dealer}`);
    console.log(`Bull owner: ${bullOwner}`);
    console.log(`Native balance: ${web3.utils.fromWei(nativeBalance, "ether")} BNB`);
    if (usdtBalance) console.log(`USDT balance (base units): ${usdtBalance.toString()}`);
    for (const choice of DEPLOYMENT_CHOICES) {
      console.log(
        `${choice.label}: ${plan[choice.key] ? "部署新合约" : `复用 ${previous[choice.key].address}`}`
      );
    }
    if (process.env.YION_ECOSYSTEM_PREFLIGHT_ONLY === "true") {
      console.log("Preflight-only mode; no transaction submitted");
      return callback();
    }

    let yion;
    let pair;
    let liquidityReceipt;
    let activationTransaction;
    let restrictedUntil;
    if (plan.yion) {
      console.log("\nDeploying YION");
      yion = await YION.new(BSC_TESTNET_USDT, BSC_TESTNET_V2_ROUTER, { from: deployer });
      const yionAmount = web3.utils.toBN(await yion.totalSupply());
      await recordContract("YION", yion, deployer, {
        usdt: BSC_TESTNET_USDT,
        router: BSC_TESTNET_V2_ROUTER,
      });

      console.log("\nCreating YION/USDT liquidity pool");
      const router = new web3.eth.Contract(ROUTER_ABI, BSC_TESTNET_V2_ROUTER);
      const factoryAddress = await router.methods.factory().call();
      const factory = new web3.eth.Contract(FACTORY_ABI, factoryAddress);
      await yion.approve(BSC_TESTNET_V2_ROUTER, yionAmount, { from: deployer });
      await usdt.methods.approve(BSC_TESTNET_V2_ROUTER, usdtAmount).send({ from: deployer });

      const latestBlock = await web3.eth.getBlock("latest");
      const deadline = Number(latestBlock.timestamp) + 20 * 60;
      liquidityReceipt = await router.methods.addLiquidity(
        yion.address,
        BSC_TESTNET_USDT,
        yionAmount.toString(),
        usdtAmount.toString(),
        yionAmount.toString(),
        usdtAmount.toString(),
        deployer,
        deadline
      ).send({ from: deployer });

      pair = await factory.methods.getPair(yion.address, BSC_TESTNET_USDT).call();
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
    } else {
      yion = await YION.at(previous.yion.address);
      pair = reusedLiquidity.pair;
      activationTransaction = reusedLiquidity.activationTransactionHash;
      restrictedUntil = reusedLiquidity.restrictedUntil;
      console.log(`\nReusing YION: ${yion.address}`);
      console.log(`Reusing YION/USDT pair: ${pair}`);
    }

    let rewardPool;
    if (plan.rewardPool) {
      console.log("\nDeploying GameRewardPool with YION");
      rewardPool = await GameRewardPool.new(yion.address, { from: deployer });
      await recordContract("GameRewardPool", rewardPool, deployer, { yion: yion.address });
    } else {
      rewardPool = await GameRewardPool.at(previous.rewardPool.address);
      console.log(`Reusing GameRewardPool: ${rewardPool.address}`);
    }

    let bullfigthing;
    if (plan.bullfigthing) {
      console.log("\nDeploying Bullfigthing");
      bullfigthing = await Bullfigthing.new(bullOwner, rewardPool.address, yion.address, { from: deployer });
      await recordContract("Bullfigthing", bullfigthing, deployer, {
        beneficiary: bullOwner,
        rewardPool: rewardPool.address,
        yion: yion.address,
      });
    } else {
      bullfigthing = await Bullfigthing.at(previous.bullfigthing.address);
      console.log(`Reusing Bullfigthing: ${bullfigthing.address}`);
    }

    let goldenFlower;
    if (plan.goldenFlower) {
      console.log("\nDeploying GoldenFlower");
      goldenFlower = await GoldenFlower.new(yion.address, dealer, rewardPool.address, { from: deployer });
      await recordContract("GoldenFlower", goldenFlower, deployer, {
        yion: yion.address,
        dealer,
        rewardPool: rewardPool.address,
      });
    } else {
      goldenFlower = await GoldenFlower.at(previous.goldenFlower.address);
      console.log(`Reusing GoldenFlower: ${goldenFlower.address}`);
    }

    let landlords;
    if (plan.landlords) {
      console.log("\nDeploying Landlords");
      landlords = await Landlords.new(yion.address, dealer, rewardPool.address, { from: deployer });
      await recordContract("Landlords", landlords, deployer, {
        yion: yion.address,
        dealer,
        rewardPool: rewardPool.address,
      });
    } else {
      landlords = await Landlords.at(previous.landlords.address);
      console.log(`Reusing Landlords: ${landlords.address}`);
    }

    if (plan.yion) {
      console.log("\nActivating YION trading and starting the 30-minute restriction");
      const activationReceipt = await yion.activateTrading(pair, { from: deployer });
      activationTransaction = activationReceipt.tx;
      restrictedUntil = (await yion.restrictedUntil()).toString();
      await recordLiquidityActivation({
        web3,
        liquidityTransactionHash: liquidityReceipt.transactionHash,
        activationTransactionHash: activationTransaction,
        restrictedUntil,
      });
    }

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
      lpHolder: plan.yion ? deployer : reusedLiquidity.provider,
      deploymentPlan: plan,
      activationTransaction,
      restrictedUntil,
    }, null, 2));
    callback();
  } catch (error) {
    callback(error);
  }
};
