const YION = artifacts.require("YIONTradingHarness");
const MockRouter = artifacts.require("MockYionRouterQuote");
const MockPair = artifacts.require("MockYionPair");
const MockUsdt = artifacts.require("MockYionUsdt");
const { expectRevert } = require("./helpers");

contract("YION", ([deployer, whitelisted, outsider, other]) => {
  const units = (value) => web3.utils.toBN(String(value)).mul(web3.utils.toBN("100000000"));
  const usdtUnits = (value) => web3.utils.toWei(String(value), "ether");
  const totalSupply = units("100000000");

  async function increaseTime(seconds) {
    await new Promise((resolve, reject) => {
      web3.currentProvider.send(
        { jsonrpc: "2.0", method: "evm_increaseTime", params: [seconds], id: Date.now() },
        (error) => error ? reject(error) : resolve()
      );
    });
    await new Promise((resolve, reject) => {
      web3.currentProvider.send(
        { jsonrpc: "2.0", method: "evm_mine", params: [], id: Date.now() + 1 },
        (error) => error ? reject(error) : resolve()
      );
    });
  }

  it("mints a fixed 8-decimal supply and hardcodes exactly 100 whitelist addresses", async () => {
    const router = await MockRouter.new({ from: deployer });
    const usdt = await MockUsdt.new({ from: deployer });
    const token = await YION.new(usdt.address, router.address, whitelisted, { from: deployer });

    assert.equal(await token.name(), "YION");
    assert.equal(await token.symbol(), "YION");
    assert.equal((await token.decimals()).toString(), "8");
    assert.equal((await token.totalSupply()).toString(), totalSupply.toString());
    assert.equal((await token.balanceOf(deployer)).toString(), totalSupply.toString());
    assert.equal(await token.whitelist("0x7c92cd77d3fba3ea33f7d94254bf3e23b25513c2"), true);
    assert.equal((await token.WHITELIST_SIZE()).toString(), "100");
  });

  it("enforces whitelist and a strict sub-200-USDT limit for 30 minutes", async () => {
    const router = await MockRouter.new({ from: deployer });
    const usdt = await MockUsdt.new({ from: deployer });
    const token = await YION.new(usdt.address, router.address, whitelisted, { from: deployer });
    const pair = await MockPair.new(token.address, usdt.address, { from: deployer });

    await usdt.mint(whitelisted, usdtUnits("1000"), { from: deployer });
    await usdt.mint(outsider, usdtUnits("1000"), { from: deployer });
    await usdt.approve(token.address, usdtUnits("1000"), { from: whitelisted });
    await usdt.approve(token.address, usdtUnits("1000"), { from: outsider });

    await token.transfer(pair.address, totalSupply, { from: deployer });
    await token.activateTrading(pair.address, { from: deployer });
    assert.equal(await token.restrictionActive(), true);

    await router.setQuotes(usdtUnits("199"), usdtUnits("199"));
    await pair.sendToken(token.address, whitelisted, units("100"), { from: deployer });
    await expectRevert(pair.sendToken(token.address, outsider, units("100"), { from: deployer }));
    await expectRevert(token.transfer(other, units("1"), { from: whitelisted }));
    await token.transfer(pair.address, units("1"), { from: whitelisted });

    await router.setQuotes(usdtUnits("200"), usdtUnits("200"));
    await expectRevert(pair.sendToken(token.address, whitelisted, units("1"), { from: deployer }));
    await expectRevert(token.transfer(pair.address, units("1"), { from: whitelisted }));

    await increaseTime(30 * 60 + 1);
    assert.equal(await token.restrictionActive(), false);
    await router.setQuotes(usdtUnits("1000"), usdtUnits("1000"));
    await pair.sendToken(token.address, outsider, units("1000"), { from: deployer });
    await token.transfer(other, units("1"), { from: outsider });
  });

  it("charges the trader a 3% USDT fee on official-pair buys and sells", async () => {
    const router = await MockRouter.new({ from: deployer });
    const usdt = await MockUsdt.new({ from: deployer });
    const token = await YION.new(usdt.address, router.address, whitelisted, { from: deployer });
    const pair = await MockPair.new(token.address, usdt.address, { from: deployer });
    const recipient = await token.FEE_RECIPIENT();

    await token.transfer(pair.address, totalSupply, { from: deployer });
    await token.activateTrading(pair.address, { from: deployer });
    await usdt.mint(whitelisted, usdtUnits("1000"), { from: deployer });
    await usdt.approve(token.address, usdtUnits("1000"), { from: whitelisted });

    await router.setQuotes(usdtUnits("100"), usdtUnits("50"));
    await pair.sendToken(token.address, whitelisted, units("100"), { from: deployer });
    assert.equal((await usdt.balanceOf(recipient)).toString(), usdtUnits("3"));

    await token.transfer(pair.address, units("10"), { from: whitelisted });
    assert.equal((await usdt.balanceOf(recipient)).toString(), usdtUnits("4.5"));
  });

  it("reverts a trade when the trader has not approved the USDT fee", async () => {
    const router = await MockRouter.new({ from: deployer });
    const usdt = await MockUsdt.new({ from: deployer });
    const token = await YION.new(usdt.address, router.address, whitelisted, { from: deployer });
    const pair = await MockPair.new(token.address, usdt.address, { from: deployer });

    await token.transfer(pair.address, totalSupply, { from: deployer });
    await token.activateTrading(pair.address, { from: deployer });
    await router.setQuotes(usdtUnits("100"), usdtUnits("100"));

    await expectRevert(pair.sendToken(token.address, whitelisted, units("100"), { from: deployer }));
  });
});
