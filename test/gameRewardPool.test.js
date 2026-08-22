const MockToken = artifacts.require("MockToken");
const GameRewardPool = artifacts.require("GameRewardPool");
const { expectRevert } = require("./helpers");

contract("GameRewardPool", ([owner, depositor, alice, outsider]) => {
  const tokens = (value) => web3.utils.toWei(String(value), "ether");

  it("deposits, records and lets a user withdraw rank rewards", async () => {
    const token = await MockToken.new({ from: owner });
    const pool = await GameRewardPool.new(token.address, { from: owner });
    assert.equal(await pool.yion(), token.address);
    await token.mint(depositor, tokens(1_000), { from: owner });
    await token.approve(pool.address, tokens(500), { from: depositor });
    await pool.depositRankReward(tokens(500), { from: depositor });

    assert.equal((await pool.rankPoolBalance()).toString(), tokens(500));
    await pool.sendRankReward([alice], [tokens(120)], { from: owner });
    const reward = await pool.getRewardAmount(alice);
    assert.equal(reward.rankReward.toString(), tokens(120));

    await pool.withdrawRankReward({ from: alice });
    assert.equal((await token.balanceOf(alice)).toString(), tokens(120));
    assert.equal((await pool.getRewardAmount(alice)).rankReward.toString(), "0");
  });

  it("rejects reward administration from a non-owner", async () => {
    const token = await MockToken.new({ from: owner });
    const pool = await GameRewardPool.new(token.address, { from: owner });
    await expectRevert(pool.sendRankReward([alice], [tokens(1)], { from: outsider }));
  });
});
