const YION = artifacts.require("YION");

const USDT = "0x5B32Cc7d18643073BDB15dAfafC5C35E736c91a5";
const ROUTER = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1";
const BUY_AMOUNT = "1000000000000000000"; // 1 testnet USDT
const FEE_BPS = web3.utils.toBN(300);
const BPS = web3.utils.toBN(10000);

const ERC20_ABI = [
  { constant: true, inputs: [{ name: "account", type: "address" }], name: "balanceOf", outputs: [{ name: "", type: "uint256" }], type: "function" },
  { constant: false, inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], name: "approve", outputs: [{ name: "", type: "bool" }], type: "function" },
];

const ROUTER_ABI = [
  { constant: true, inputs: [{ name: "amountIn", type: "uint256" }, { name: "path", type: "address[]" }], name: "getAmountsOut", outputs: [{ name: "amounts", type: "uint256[]" }], type: "function" },
  { constant: false, inputs: [{ name: "amountIn", type: "uint256" }, { name: "amountOutMin", type: "uint256" }, { name: "path", type: "address[]" }, { name: "to", type: "address" }, { name: "deadline", type: "uint256" }], name: "swapExactTokensForTokensSupportingFeeOnTransferTokens", outputs: [], type: "function" },
];

function withOnePercentSlippage(amount) {
  return web3.utils.toBN(amount).mul(web3.utils.toBN(99)).div(web3.utils.toBN(100));
}

module.exports = async function (callback) {
  try {
    if (Number(await web3.eth.getChainId()) !== 97) throw new Error("BSC Testnet only");
    if (!process.env.YION_ADDRESS) throw new Error("YION_ADDRESS is required");
    if (!process.env.YION_TRADE_STEP) throw new Error("YION_TRADE_STEP is required");

    const [trader] = await web3.eth.getAccounts();
    const yion = await YION.at(process.env.YION_ADDRESS);
    const stablecoin = new web3.eth.Contract(ERC20_ABI, USDT);
    const router = new web3.eth.Contract(ROUTER_ABI, ROUTER);
    const step = process.env.YION_TRADE_STEP;
    const latest = await web3.eth.getBlock("latest");
    const tradeDeadline = Number(latest.timestamp) + 10 * 60;

    if (step === "approve-buy") {
      const receipt = await stablecoin.methods.approve(ROUTER, BUY_AMOUNT).send({ from: trader });
      console.log(`USDT approval to Pancake Router: ${receipt.transactionHash}`);
      return callback();
    }

    if (step === "buy") {
      const quote = await router.methods.getAmountsOut(BUY_AMOUNT, [USDT, yion.address]).call();
      const exempt = await yion.feeExempt(trader);
      const expected = exempt
        ? web3.utils.toBN(quote[1])
        : web3.utils.toBN(quote[1]).mul(BPS.sub(FEE_BPS)).div(BPS);
      const yionBefore = web3.utils.toBN(await yion.balanceOf(trader));
      const usdtBefore = web3.utils.toBN(await stablecoin.methods.balanceOf(trader).call());
      const receipt = await router.methods
        .swapExactTokensForTokensSupportingFeeOnTransferTokens(
          BUY_AMOUNT,
          withOnePercentSlippage(expected).toString(),
          [USDT, yion.address],
          trader,
          tradeDeadline
        )
        .send({ from: trader, gas: 600000 });
      const yionAfter = web3.utils.toBN(await yion.balanceOf(trader));
      const usdtAfter = web3.utils.toBN(await stablecoin.methods.balanceOf(trader).call());
      console.log(JSON.stringify({
        transactionHash: receipt.transactionHash,
        traderUsdtChange: usdtAfter.sub(usdtBefore).toString(),
        yionReceived: yionAfter.sub(yionBefore).toString(),
      }, null, 2));
      return callback();
    }

    if (step === "approve-sell") {
      const amount = (await yion.balanceOf(trader)).toString();
      if (amount === "0") throw new Error("No YION available to approve");
      const receipt = await yion.approve(ROUTER, amount, { from: trader });
      console.log(`YION approval to Pancake Router: ${receipt.tx}`);
      return callback();
    }

    if (step === "sell") {
      const amount = web3.utils.toBN(await yion.balanceOf(trader));
      if (amount.isZero()) throw new Error("No YION available to sell");
      const exempt = await yion.feeExempt(trader);
      const pairInput = exempt ? amount : amount.mul(BPS.sub(FEE_BPS)).div(BPS);
      const quote = await router.methods.getAmountsOut(pairInput.toString(), [yion.address, USDT]).call();
      const usdtBefore = web3.utils.toBN(await stablecoin.methods.balanceOf(trader).call());
      const receipt = await router.methods
        .swapExactTokensForTokensSupportingFeeOnTransferTokens(
          amount.toString(),
          withOnePercentSlippage(quote[1]).toString(),
          [yion.address, USDT],
          trader,
          tradeDeadline
        )
        .send({ from: trader, gas: 900000 });
      const usdtAfter = web3.utils.toBN(await stablecoin.methods.balanceOf(trader).call());
      console.log(JSON.stringify({
        transactionHash: receipt.transactionHash,
        yionSubmitted: amount.toString(),
        traderUsdtReceived: usdtAfter.sub(usdtBefore).toString(),
      }, null, 2));
      return callback();
    }

    throw new Error(`Unsupported YION_TRADE_STEP: ${step}`);
  } catch (error) {
    callback(error);
  }
};
