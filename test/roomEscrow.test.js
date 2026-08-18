const MockToken = artifacts.require("MockToken");
const GameRewardPool = artifacts.require("GameRewardPool");
const Landlords = artifacts.require("LandlordsPricingHarness");
const GoldenFlower = artifacts.require("GoldenFlowerPricingHarness");
const { expectRevert } = require("./helpers");

contract("Room escrow games", ([owner, dealer, player1, player2, player3, outsider]) => {
  const tokens = (value) => web3.utils.toWei(String(value), "ether");
  let token;
  let pool;

  beforeEach(async () => {
    token = await MockToken.new({ from: owner });
    pool = await GameRewardPool.new(token.address, { from: owner });
    for (const player of [player1, player2, player3]) {
      await token.mint(player, tokens(200_000), { from: owner });
    }
  });

  async function approveAndJoin(game, method, roomId, players, deposit) {
    for (const player of players) {
      await token.approve(game.address, deposit, { from: player });
      await game[method](roomId, { from: player });
    }
  }

  it("locks and refunds a Landlords room", async () => {
    const game = await Landlords.new(token.address, dealer, pool.address, { from: owner });
    const deposit = tokens(2);
    await approveAndJoin(game, "joinRoom", 1, [player1, player2, player3], deposit);

    let room = await game.getRoomInfo(1);
    assert.equal(room.values[0].toString(), "1", "room should be locked");
    assert.equal(room.values[3].toString(), "3");
    assert.equal(room.values[4].toString(), "200", "bet price is 2.00 USDT");
    assert.equal(room.values[5].toString(), "200", "entry price is 2.00 USDT");
    assert.equal((await game.TOTAL_ROOMS()).toString(), "12");
    const lastRoom = await game.getRoomInfo(12);
    assert.equal(lastRoom.values[4].toString(), "200");
    assert.equal(lastRoom.values[5].toString(), "200");
    await expectRevert(game.getRoomInfo(13));
    assert.equal(await game.usdtToken(), "0x5B32Cc7d18643073BDB15dAfafC5C35E736c91a5");
    await expectRevert(game.refundRoom(1, { from: outsider }));

    await game.refundRoom(1, { from: dealer });
    room = await game.getRoomInfo(1);
    assert.equal(room.values[0].toString(), "0");
    assert.equal(room.values[1].toString(), "2");
    assert.equal((await token.balanceOf(player1)).toString(), tokens(200_000));
  });

  it("falls back to token ratios when Landlords USDT quote exceeds escrow", async () => {
    const game = await Landlords.new(token.address, dealer, pool.address, { from: owner });
    const deposit = tokens(2);
    await approveAndJoin(game, "joinRoom", 1, [player1, player2, player3], deposit);

    await game.setQuoteBps(11_000, { from: owner });
    const beforeWinner = await token.balanceOf(player1);
    const settlement = await game.settleRoom(
      1,
      [outsider, player1],
      [100, 100, 100, 1, 0, 0, 210],
      { from: dealer }
    );

    const afterWinner = await token.balanceOf(player1);
    assert.equal(afterWinner.sub(beforeWinner).toString(), tokens(3.1));
    assert.equal((await pool.rankPoolBalance()).toString(), tokens(0.15));
    assert.equal((await pool.replenishPoolBalance()).toString(), tokens(0.3));
    assert.equal((await token.balanceOf(game.address)).toString(), "0");
    const event = settlement.logs.find((log) => log.event === "SettlementModeSelected").args;
    assert.equal(event.usdtMode, false);
    assert.equal(event.escrowToken.toString(), tokens(6));
    assert.equal(event.quotedTokenRequired.toString(), tokens(6.6));
    assert.equal(event.paidToken.toString(), tokens(6));
  });

  it("settles Landlords at the current USDT value when the token price rises", async () => {
    const game = await Landlords.new(token.address, dealer, pool.address, { from: owner });
    const deposit = tokens(2);
    await approveAndJoin(game, "joinRoom", 1, [player1, player2, player3], deposit);

    await game.setQuoteBps(8_000, { from: owner });
    const beforeWinner = await token.balanceOf(player1);
    const settlement = await game.settleRoom(
      1,
      [outsider, player1],
      [100, 100, 100, 1, 0, 0, 210],
      { from: dealer }
    );

    const event = settlement.logs.find((log) => log.event === "SettlementModeSelected").args;
    assert.equal(event.usdtMode, true);
    assert.equal(event.escrowToken.toString(), tokens(6));
    assert.equal(event.quotedTokenRequired.toString(), tokens(4.8));
    assert.equal(event.paidToken.toString(), tokens(4.8));
    assert.equal((await token.balanceOf(player1)).sub(beforeWinner).toString(), tokens(2.48));
    assert.equal((await pool.rankPoolBalance()).toString(), tokens(0.12));
    assert.equal((await pool.replenishPoolBalance()).toString(), tokens(0.24));
    assert.equal((await token.balanceOf(game.address)).toString(), tokens(1.2));
  });

  it("locks and refunds a three-player GoldenFlower room", async () => {
    const game = await GoldenFlower.new(token.address, dealer, pool.address, { from: owner });
    const deposit = tokens(2);
    await approveAndJoin(game, "joinRoom", 1, [player1, player2, player3], deposit);

    let room = await game.getRoomInfo(1);
    assert.equal(room.values[0].toString(), "1");
    assert.equal(room.values[6].toString(), "3");
    assert.equal(room.values[4].toString(), "200");
    assert.equal(room.values[5].toString(), "200");
    assert.equal((await game.TOTAL_ROOMS()).toString(), "20");
    const lastRoom = await game.getRoomInfo(20);
    assert.equal(lastRoom.values[4].toString(), "400");
    assert.equal(lastRoom.values[5].toString(), "400");
    assert.equal(lastRoom.values[6].toString(), "5");
    await expectRevert(game.getRoomInfo(21));

    await game.refundRoom(1, { from: dealer });
    room = await game.getRoomInfo(1);
    assert.equal(room.values[0].toString(), "0");
    assert.equal(room.values[1].toString(), "2");
  });

  it("settles GoldenFlower in USDT mode when the settlement quote fits escrow", async () => {
    const game = await GoldenFlower.new(token.address, dealer, pool.address, { from: owner });
    const deposit = tokens(2);
    await approveAndJoin(game, "joinRoom", 1, [player1, player2, player3], deposit);

    await game.setQuoteBps(9_000, { from: owner });
    const settlement = await game.settleRoom(
      1,
      [player1, outsider, owner, dealer],
      [100, 100, 100, 0, 0, 1, 1, 9, 6],
      { from: dealer }
    );

    assert.equal((await pool.rankPoolBalance()).toString(), tokens(0.135));
    assert.equal((await pool.replenishPoolBalance()).toString(), tokens(0.27));
    assert.equal((await token.balanceOf(game.address)).toString(), tokens(0.6));
    const event = settlement.logs.find((log) => log.event === "SettlementModeSelected").args;
    assert.equal(event.usdtMode, true);
    assert.equal(event.escrowToken.toString(), tokens(6));
    assert.equal(event.quotedTokenRequired.toString(), tokens(5.4));
    assert.equal(event.paidToken.toString(), tokens(5.4));
  });

  it("falls back to the room escrow when the GoldenFlower token price falls", async () => {
    const game = await GoldenFlower.new(token.address, dealer, pool.address, { from: owner });
    const deposit = tokens(2);
    await approveAndJoin(game, "joinRoom", 1, [player1, player2, player3], deposit);

    await game.setQuoteBps(11_000, { from: owner });
    const beforeWinner = await token.balanceOf(player1);
    const settlement = await game.settleRoom(
      1,
      [player1, outsider, owner, dealer],
      [100, 100, 100, 0, 0, 1, 1, 9, 6],
      { from: dealer }
    );

    const event = settlement.logs.find((log) => log.event === "SettlementModeSelected").args;
    assert.equal(event.usdtMode, false);
    assert.equal(event.escrowToken.toString(), tokens(6));
    assert.equal(event.quotedTokenRequired.toString(), tokens(6.6));
    assert.equal(event.paidToken.toString(), tokens(6));
    assert.equal((await token.balanceOf(player1)).sub(beforeWinner).toString(), tokens(3.1));
    assert.equal((await pool.rankPoolBalance()).toString(), tokens(0.15));
    assert.equal((await pool.replenishPoolBalance()).toString(), tokens(0.3));
    assert.equal((await token.balanceOf(game.address)).toString(), "0");
  });
});
