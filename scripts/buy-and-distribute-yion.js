const fs = require("fs");
const path = require("path");
const readline = require("readline");

const YION = artifacts.require("YION");

const EXPECTED_BUYER = "0x7c92cd77d3fbA3ea33f7D94254bf3E23B25513C2";
const TOTAL_YION = "1000000";
const DEFAULT_SLIPPAGE_BPS = 200;
const BPS = web3.utils.toBN(10_000);
const FEE_BPS = web3.utils.toBN(300);
const REGISTRY_PATH = path.resolve(__dirname, "..", "deployments", "bsc-testnet-97.json");

const RECIPIENTS = [
  "0x291A2516ab886E947A03De9e48E7C886C6ec3D5C",
  "0x3972a203957936E8aBa8dbf327096d3B669c908D",
  "0xFb3F1dD098795666846c0B1F6F8E67105927E3d7",
  "0xA2d62ef01D2919ebF2B7f6A282d4102ac6cE4ce6",
];

const ERC20_ABI = [
  { constant: true, inputs: [], name: "decimals", outputs: [{ name: "", type: "uint8" }], type: "function" },
  { constant: true, inputs: [{ name: "account", type: "address" }], name: "balanceOf", outputs: [{ name: "", type: "uint256" }], type: "function" },
  { constant: true, inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }], name: "allowance", outputs: [{ name: "", type: "uint256" }], type: "function" },
  { constant: false, inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], name: "approve", outputs: [{ name: "", type: "bool" }], type: "function" },
];

const ROUTER_ABI = [
  {
    constant: true,
    inputs: [{ name: "amountOut", type: "uint256" }, { name: "path", type: "address[]" }],
    name: "getAmountsIn",
    outputs: [{ name: "amounts", type: "uint256[]" }],
    type: "function",
  },
  {
    constant: false,
    inputs: [
      { name: "amountOut", type: "uint256" },
      { name: "amountInMax", type: "uint256" },
      { name: "path", type: "address[]" },
      { name: "to", type: "address" },
      { name: "deadline", type: "uint256" },
    ],
    name: "swapTokensForExactTokens",
    outputs: [{ name: "amounts", type: "uint256[]" }],
    type: "function",
  },
];

function latestSuccessful(items, predicate) {
  return [...items].reverse().find((item) => item.status === "success" && predicate(item));
}

function decimalAmount(value, decimals) {
  return web3.utils.toBN(value).mul(web3.utils.toBN(10).pow(web3.utils.toBN(decimals)));
}

function ceilDiv(value, divisor) {
  return value.add(divisor).subn(1).div(divisor);
}

function formatUnits(value, decimals) {
  const amount = web3.utils.toBN(value);
  const unit = web3.utils.toBN(10).pow(web3.utils.toBN(decimals));
  const integer = amount.div(unit).toString();
  const fraction = amount.mod(unit).toString().padStart(decimals, "0").replace(/0+$/, "");
  return fraction ? `${integer}.${fraction}` : integer;
}

function confirmationRequired() {
  return !["1", "true", "yes"].includes(
    String(process.env.CONFIRM_YION_DISTRIBUTION || "").trim().toLowerCase()
  );
}

function askConfirmation(message) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(message, (answer) => {
      rl.close();
      resolve(answer.trim().toLowerCase() === "yes");
    });
  });
}

module.exports = async function (callback) {
  try {
    const chainId = Number(await web3.eth.getChainId());
    if (chainId !== 97) throw new Error(`BSC Testnet (97) only, got ${chainId}`);

    const [buyer] = await web3.eth.getAccounts();
    if (buyer.toLowerCase() !== EXPECTED_BUYER.toLowerCase()) {
      throw new Error(`Signer mismatch: expected ${EXPECTED_BUYER}, got ${buyer}`);
    }

    const registry = JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
    const yionRecord = latestSuccessful(
      registry.deployments,
      (item) => item.contract === "YION"
    );
    if (!yionRecord) throw new Error("No successful YION deployment found");
    const liquidity = latestSuccessful(
      registry.liquidityPools || [],
      (item) => item.token.toLowerCase() === yionRecord.address.toLowerCase()
    );
    if (!liquidity) throw new Error(`No liquidity pool found for YION ${yionRecord.address}`);
    if (!liquidity.activationTransactionHash) throw new Error("Latest YION trading is not activated");

    const recipients = RECIPIENTS.map((address) => web3.utils.toChecksumAddress(address));
    if (new Set(recipients.map((address) => address.toLowerCase())).size !== recipients.length) {
      throw new Error("Duplicate recipient address");
    }

    const yion = await YION.at(yionRecord.address);
    const usdtAddress = await yion.usdt();
    const routerAddress = await yion.router();
    const activePair = await yion.liquidityPair();
    if (activePair.toLowerCase() !== liquidity.pair.toLowerCase()) {
      throw new Error(`YION active Pair ${activePair} does not match registry ${liquidity.pair}`);
    }
    if (routerAddress.toLowerCase() !== liquidity.router.toLowerCase()) {
      throw new Error(`YION Router ${routerAddress} does not match registry ${liquidity.router}`);
    }
    if (await yion.restrictionActive()) {
      throw new Error("YION is still in the 30-minute restricted period; ordinary transfers are disabled");
    }

    const yionDecimals = Number(await yion.decimals());
    const usdt = new web3.eth.Contract(ERC20_ABI, usdtAddress);
    const usdtDecimals = Number(await usdt.methods.decimals().call());
    const router = new web3.eth.Contract(ROUTER_ABI, routerAddress);
    const targetNetYion = decimalAmount(TOTAL_YION, yionDecimals);
    const perRecipient = targetNetYion.divn(recipients.length);
    if (!perRecipient.muln(recipients.length).eq(targetNetYion)) {
      throw new Error("Total YION amount cannot be divided equally among recipients");
    }

    const feeExempt = await yion.feeExempt(buyer);
    const routerGrossYion = feeExempt
      ? targetNetYion
      : ceilDiv(targetNetYion.mul(BPS), BPS.sub(FEE_BPS));
    const amountsIn = await router.methods
      .getAmountsIn(routerGrossYion.toString(), [usdtAddress, yion.address])
      .call();
    const quotedUsdt = web3.utils.toBN(amountsIn[0]);
    const slippageBps = Number(process.env.YION_BUY_SLIPPAGE_BPS || DEFAULT_SLIPPAGE_BPS);
    if (!Number.isInteger(slippageBps) || slippageBps < 0 || slippageBps > 5_000) {
      throw new Error("YION_BUY_SLIPPAGE_BPS must be an integer between 0 and 5000");
    }
    const maxUsdt = ceilDiv(quotedUsdt.mul(BPS.addn(slippageBps)), BPS);
    const usdtBalance = web3.utils.toBN(await usdt.methods.balanceOf(buyer).call());
    if (usdtBalance.lt(maxUsdt)) {
      throw new Error(
        `Insufficient USDT: need up to ${formatUnits(maxUsdt, usdtDecimals)}, ` +
        `have ${formatUnits(usdtBalance, usdtDecimals)}`
      );
    }

    console.log(JSON.stringify({
      network: "BSC Testnet",
      buyer,
      yion: yion.address,
      pair: activePair,
      router: routerAddress,
      totalYionToBuy: formatUnits(targetNetYion, yionDecimals),
      yionPerRecipient: formatUnits(perRecipient, yionDecimals),
      recipients,
      buyerFeeExempt: feeExempt,
      quotedUsdt: formatUnits(quotedUsdt, usdtDecimals),
      maxUsdtWithSlippage: formatUnits(maxUsdt, usdtDecimals),
      slippageBps,
    }, null, 2));

    if (process.env.YION_DISTRIBUTION_DRY_RUN === "true") {
      console.log("Dry-run complete; no transaction submitted");
      return callback();
    }

    if (confirmationRequired()) {
      const confirmed = await askConfirmation(
        `输入 yes 确认买入 ${TOTAL_YION} YION，并向4个地址各发送250000 YION: `
      );
      if (!confirmed) throw new Error("Operation cancelled");
    }

    const allowance = web3.utils.toBN(
      await usdt.methods.allowance(buyer, routerAddress).call()
    );
    let approvalTransaction;
    if (allowance.lt(maxUsdt)) {
      const approval = await usdt.methods
        .approve(routerAddress, maxUsdt.toString())
        .send({ from: buyer });
      approvalTransaction = approval.transactionHash;
      console.log(`USDT approval: ${approvalTransaction}`);
    }

    const yionBefore = web3.utils.toBN(await yion.balanceOf(buyer));
    const latestBlock = await web3.eth.getBlock("latest");
    const deadline = Number(latestBlock.timestamp) + 20 * 60;
    const purchase = await router.methods
      .swapTokensForExactTokens(
        routerGrossYion.toString(),
        maxUsdt.toString(),
        [usdtAddress, yion.address],
        buyer,
        deadline
      )
      .send({ from: buyer, gas: 900000 });
    const yionAfter = web3.utils.toBN(await yion.balanceOf(buyer));
    const received = yionAfter.sub(yionBefore);
    if (received.lt(targetNetYion)) {
      throw new Error(
        `Purchase received only ${formatUnits(received, yionDecimals)} YION; distribution not started`
      );
    }
    console.log(`YION purchase: ${purchase.transactionHash}`);

    const transfers = [];
    for (const recipient of recipients) {
      const receipt = await yion.transfer(recipient, perRecipient.toString(), { from: buyer });
      transfers.push({ recipient, amount: perRecipient.toString(), transactionHash: receipt.tx });
      console.log(`Transferred 250000 YION to ${recipient}: ${receipt.tx}`);
    }

    console.log(JSON.stringify({
      approvalTransaction,
      purchaseTransaction: purchase.transactionHash,
      yionReceived: received.toString(),
      transfers,
    }, null, 2));
    callback();
  } catch (error) {
    callback(error);
  }
};
