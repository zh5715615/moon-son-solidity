const MockToken = artifacts.require("MockToken");
const GameRewardPool = artifacts.require("GameRewardPool");
const Bullfigthing = artifacts.require("BullfigthingPricingHarness");

contract("Bullfigthing", (accounts) => {
  const [owner, winner, player2, player3, player4, player5] = accounts;
  const players = [winner, player2, player3, player4, player5];
  const tokens = (value) => web3.utils.toWei(String(value), "ether");

  it("settles a full room and funds both reward pools", async () => {
    const token = await MockToken.new({ from: owner });
    const pool = await GameRewardPool.new(token.address, { from: owner });
    const game = await Bullfigthing.new(owner, pool.address, token.address, { from: owner });
    const quoteBps = [10_000, 11_000, 12_000, 13_000, 14_000];
    const deposits = quoteBps.map((bps) => web3.utils.toBN(tokens(30)).muln(bps).divn(10_000));

    for (let i = 0; i < players.length; i++) {
      const player = players[i];
      await game.setQuoteBps(quoteBps[i], { from: owner });
      await token.mint(player, deposits[i], { from: owner });
      await token.approve(game.address, deposits[i], { from: player });
      await game.enterTheRoom(0, { from: player });
    }

    const beforeWinner = await token.balanceOf(winner);
    const settlement = await game.sendInstantReward(0, winner, [], [], { from: owner });
    const expectedWinner = web3.utils.toBN(tokens(126));
    const afterWinner = await token.balanceOf(winner);

    assert.equal(afterWinner.sub(beforeWinner).toString(), expectedWinner.toString());
    assert.equal((await pool.rankPoolBalance()).toString(), tokens(9));
    assert.equal((await pool.replenishPoolBalance()).toString(), tokens(18));
    assert.equal((await token.balanceOf(game.address)).toString(), "0");
    assert.equal(settlement.logs.find((log) => log.event === "SettlementModeSelected").args.usdtMode, false);
    const room = await game.getRoomInfo(0);
    assert.equal(room.values[2].toString(), "0");
    assert.equal(room.values[3].toString(), "1");
    assert.equal(room.values[4].toString(), "2");
    assert.equal((await game.quoteTokenAmount(3000)).toString(), tokens(42));
  });
});
