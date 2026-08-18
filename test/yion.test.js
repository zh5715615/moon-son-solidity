const YION = artifacts.require("YIONTradingHarness");
const MockRouter = artifacts.require("MockYionRouterQuote");
const MockPair = artifacts.require("MockYionPair");
const MockUsdt = artifacts.require("MockYionUsdt");
const MockUsdt6 = artifacts.require("MockYionUsdt6");
const { expectRevert } = require("./helpers");

contract("YION", ([deployer, whitelisted, outsider, other]) => {
  const BN = web3.utils.toBN;
  const yion = (value) => BN(value).mul(BN("100000000"));
  const usdt = (value) => BN(web3.utils.toWei(value.toString(), "ether"));
  const totalSupply = yion("100000000");
  const deadline = "9999999999";

  async function increaseTime(seconds) {
    await new Promise((resolve, reject) => {
      web3.currentProvider.send(
        { jsonrpc: "2.0", method: "evm_increaseTime", params: [seconds], id: Date.now() },
        (error) => (error ? reject(error) : resolve())
      );
    });
    await new Promise((resolve, reject) => {
      web3.currentProvider.send(
        { jsonrpc: "2.0", method: "evm_mine", params: [], id: Date.now() + 1 },
        (error) => (error ? reject(error) : resolve())
      );
    });
  }

  async function fixture() {
    const router = await MockRouter.new({ from: deployer });
    const stablecoin = await MockUsdt.new({ from: deployer });
    const token = await YION.new(stablecoin.address, router.address, whitelisted, {
      from: deployer,
    });
    const pair = await MockPair.new(token.address, stablecoin.address, { from: deployer });
    await router.configure(pair.address, token.address, stablecoin.address);
    await token.transfer(pair.address, totalSupply, { from: deployer });
    await stablecoin.mint(pair.address, usdt("10000"));
    await token.activateTrading(pair.address, { from: deployer });
    return { router, stablecoin, token, pair };
  }

  async function buy({ router, stablecoin, token, trader, amount }) {
    await stablecoin.approve(router.address, amount, { from: trader });
    return router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
      amount,
      0,
      [stablecoin.address, token.address],
      trader,
      deadline,
      { from: trader }
    );
  }

  async function sell({ router, stablecoin, token, trader, amount }) {
    await token.approve(router.address, amount, { from: trader });
    return router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
      amount,
      0,
      [token.address, stablecoin.address],
      trader,
      deadline,
      { from: trader }
    );
  }

  it("has fixed 8-decimal supply, launch whitelist and default fee exemptions", async () => {
    const { token } = await fixture();
    assert.equal((await token.decimals()).toString(), "8");
    assert.equal((await token.totalSupply()).toString(), totalSupply.toString());
    assert.equal(await token.whitelist("0x7c92cd77d3fba3ea33f7d94254bf3e23b25513c2"), true);
    assert.equal(await token.feeExempt(deployer), true);
    assert.equal(await token.feeExempt(token.address), true);
    assert.equal(await token.feeExempt(whitelisted), false);
  });

  it("derives the 200-USDT limit from the configured USDT decimals", async () => {
    const router = await MockRouter.new({ from: deployer });
    const stablecoin = await MockUsdt6.new({ from: deployer });
    const token = await YION.new(stablecoin.address, router.address, whitelisted, {
      from: deployer,
    });

    assert.equal((await token.MAX_TRADE_USDT()).toString(), "200000000");
  });

  it("charges a 3% YION fee on a native Pancake-style buy", async () => {
    const f = await fixture();
    await f.router.setQuotes(yion("1000000"), usdt("100"), usdt("50"));
    await f.stablecoin.mint(whitelisted, usdt("100"));

    await buy({ ...f, trader: whitelisted, amount: usdt("100") });

    const recipient = await f.token.FEE_RECIPIENT();
    assert.equal((await f.token.balanceOf(whitelisted)).toString(), yion("970000").toString());
    assert.equal((await f.token.balanceOf(recipient)).toString(), yion("30000").toString());
    assert.equal((await f.token.balanceOf(f.token.address)).toString(), "0");
    assert.equal((await f.stablecoin.balanceOf(whitelisted)).toString(), "0");
    assert.equal((await f.stablecoin.balanceOf(f.pair.address)).toString(), usdt("10100").toString());
  });

  it("charges a 3% YION fee on a native Pancake-style sell", async () => {
    const f = await fixture();
    await f.router.setQuotes(yion("1000000"), usdt("100"), usdt("50"));
    await f.stablecoin.mint(whitelisted, usdt("100"));
    await buy({ ...f, trader: whitelisted, amount: usdt("100") });
    const pairBefore = await f.token.balanceOf(f.pair.address);

    await sell({ ...f, trader: whitelisted, amount: yion("100000") });

    const recipient = await f.token.FEE_RECIPIENT();
    const pairAfter = await f.token.balanceOf(f.pair.address);
    assert.equal(pairAfter.sub(pairBefore).toString(), yion("97000").toString());
    assert.equal((await f.token.balanceOf(recipient)).toString(), yion("33000").toString());
    assert.equal((await f.token.balanceOf(f.token.address)).toString(), "0");
    assert.equal((await f.stablecoin.balanceOf(whitelisted)).toString(), usdt("50").toString());
  });

  it("lets only the launcher manage the separate fee-exemption whitelist", async () => {
    const f = await fixture();
    await expectRevert(f.token.setFeeExempt(whitelisted, true, { from: outsider }));
    await f.token.setFeeExempt(whitelisted, true, { from: deployer });
    assert.equal(await f.token.feeExempt(whitelisted), true);
    await f.router.setQuotes(yion("1000000"), usdt("100"), usdt("50"));
    await f.stablecoin.mint(whitelisted, usdt("100"));

    await buy({ ...f, trader: whitelisted, amount: usdt("100") });

    const recipient = await f.token.FEE_RECIPIENT();
    assert.equal((await f.token.balanceOf(whitelisted)).toString(), yion("1000000").toString());
    assert.equal((await f.token.balanceOf(recipient)).toString(), "0");
    await f.token.setFeeExempt(whitelisted, false, { from: deployer });
    assert.equal(await f.token.feeExempt(whitelisted), false);
  });

  it("enforces the 30-minute launch whitelist and allows trades up to 200 USDT", async () => {
    const f = await fixture();
    await f.router.setQuotes(yion("1000"), usdt("199"), usdt("199"));
    await f.stablecoin.mint(whitelisted, usdt("400"));
    await f.stablecoin.mint(outsider, usdt("400"));
    await buy({ ...f, trader: whitelisted, amount: usdt("199") });
    await expectRevert(buy({ ...f, trader: outsider, amount: usdt("199") }));
    await f.router.setQuotes(yion("1000"), usdt("200"), usdt("200"));
    await buy({ ...f, trader: whitelisted, amount: usdt("200") });
    await f.router.setQuotes(yion("1000"), usdt("201"), usdt("201"));
    await expectRevert(buy({ ...f, trader: whitelisted, amount: usdt("201") }));
    await expectRevert(f.token.transfer(other, 1, { from: whitelisted }));

    await increaseTime(30 * 60 + 1);
    await buy({ ...f, trader: outsider, amount: usdt("200") });
    await f.token.transfer(other, 1, { from: outsider });
    assert.equal((await f.token.balanceOf(other)).toString(), "1");
  });

});
