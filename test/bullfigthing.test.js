const MockToken = artifacts.require("MockToken");
const GameRewardPool = artifacts.require("GameRewardPool");
const Bullfigthing = artifacts.require("BullfigthingPricingHarness");

contract("Bullfigthing", (accounts) => {
  const [owner, winner, player2, player3, player4, player5] = accounts;
  const players = [winner, player2, player3, player4, player5];
  const tokens = (value) => web3.utils.toWei(String(value), "ether");

  it("uses the current USDT-equivalent token amount when the token price rises", async () => {
    const token = await MockToken.new({ from: owner });
    const pool = await GameRewardPool.new(token.address, { from: owner });
    const game = await Bullfigthing.new(owner, pool.address, token.address, { from: owner });
    const entryAmount = tokens(5);

    for (const player of players) {
      await token.mint(player, entryAmount, { from: owner });
      await token.approve(game.address, entryAmount, { from: player });
      await game.enterTheRoom(0, { from: player });
    }

    // The same 25 USDT is now worth 20 tokens, so only 20 tokens are paid.
    await game.setQuoteBps(8_000, { from: owner });
    const beforeWinner = await token.balanceOf(winner);
    const settlement = await game.sendInstantReward(0, winner, [], [], { from: owner });
    const event = settlement.logs.find((log) => log.event === "SettlementModeSelected");

    assert.equal(event.args.usdtMode, true);
    assert.equal(event.args.escrowToken.toString(), tokens(25));
    assert.equal(event.args.quotedTokenRequired.toString(), tokens(20));
    assert.equal(event.args.paidToken.toString(), tokens(20));
    assert.equal((await token.balanceOf(winner)).sub(beforeWinner).toString(), tokens(14));
    assert.equal((await pool.rankPoolBalance()).toString(), tokens(1));
    assert.equal((await pool.replenishPoolBalance()).toString(), tokens(2));
    assert.equal((await token.balanceOf(game.address)).toString(), tokens(5));
  });

  it("settles a full room and funds both reward pools", async () => {
    const token = await MockToken.new({ from: owner });
    const pool = await GameRewardPool.new(token.address, { from: owner });
    const game = await Bullfigthing.new(owner, pool.address, token.address, { from: owner });
    const quoteBps = [10_000, 11_000, 12_000, 13_000, 14_000];
    const deposits = quoteBps.map((bps) => web3.utils.toBN(tokens(5)).muln(bps).divn(10_000));

    for (let i = 0; i < players.length; i++) {
      const player = players[i];
      await game.setQuoteBps(quoteBps[i], { from: owner });
      await token.mint(player, deposits[i], { from: owner });
      await token.approve(game.address, deposits[i], { from: player });
      await game.enterTheRoom(0, { from: player });
    }

    const beforeWinner = await token.balanceOf(winner);
    const settlement = await game.sendInstantReward(0, winner, [], [], { from: owner });
    const expectedWinner = web3.utils.toBN(tokens(21));
    const afterWinner = await token.balanceOf(winner);

    assert.equal(afterWinner.sub(beforeWinner).toString(), expectedWinner.toString());
    assert.equal((await pool.rankPoolBalance()).toString(), tokens(1.5));
    assert.equal((await pool.replenishPoolBalance()).toString(), tokens(3));
    assert.equal((await token.balanceOf(game.address)).toString(), "0");
    assert.equal(settlement.logs.find((log) => log.event === "SettlementModeSelected").args.usdtMode, false);
    const room = await game.getRoomInfo(0);
    assert.equal(room.values[2].toString(), "0");
    assert.equal(room.values[3].toString(), "1");
    assert.equal(room.values[4].toString(), "2");
    assert.equal((await game.TOTAL_ROOMS()).toString(), "15");
    assert.equal(room.values[1].toString(), "500");
    const lastRoom = await game.getRoomInfo(14);
    assert.equal(lastRoom.values[1].toString(), "500");
    assert.equal((await game.quoteTokenAmount(500)).toString(), tokens(7));
  });
});
