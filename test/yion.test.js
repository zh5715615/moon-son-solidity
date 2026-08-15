const YION = artifacts.require("YIONTradingHarness");
const MockRouter = artifacts.require("MockYionRouterQuote");
const MockPair = artifacts.require("MockYionPair");
const { expectRevert } = require("./helpers");

contract("YION", ([deployer, whitelisted, outsider, other, usdt]) => {
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
    const token = await YION.new(usdt, router.address, whitelisted, { from: deployer });

    assert.equal(await token.name(), "YION");
    assert.equal(await token.symbol(), "YION");
    assert.equal((await token.decimals()).toString(), "8");
    assert.equal((await token.totalSupply()).toString(), totalSupply.toString());
    assert.equal((await token.balanceOf(deployer)).toString(), totalSupply.toString());
    assert.equal(await token.whitelist("0xd9f200aff52895f1bdd221a883071e8ba94c30d0"), true);
    assert.equal((await token.WHITELIST_SIZE()).toString(), "100");
  });

  it("enforces whitelist and a strict sub-200-USDT limit for 30 minutes", async () => {
    const router = await MockRouter.new({ from: deployer });
    const token = await YION.new(usdt, router.address, whitelisted, { from: deployer });
    const pair = await MockPair.new(token.address, usdt, { from: deployer });

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
});
