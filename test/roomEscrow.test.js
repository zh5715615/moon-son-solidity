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
    const deposit = tokens(200);
    await approveAndJoin(game, "joinRoom", 1, [player1, player2, player3], deposit);

    let room = await game.getRoomInfo(1);
    assert.equal(room.values[0].toString(), "1", "room should be locked");
    assert.equal(room.values[3].toString(), "3");
    assert.equal(room.values[4].toString(), "1000", "bet price is 10.00 USDT");
    assert.equal(room.values[5].toString(), "20000", "deposit price is 200.00 USDT");
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
    const deposit = tokens(200);
    await approveAndJoin(game, "joinRoom", 1, [player1, player2, player3], deposit);

    await game.setQuoteBps(11_000, { from: owner });
    const beforeWinner = await token.balanceOf(player1);
    const settlement = await game.settleRoom(
      1,
      [outsider, player1],
      [10_000, 10_000, 10_000, 1, 0, 0, 21_000],
      { from: dealer }
    );

    const afterWinner = await token.balanceOf(player1);
    assert.equal(afterWinner.sub(beforeWinner).toString(), tokens(310));
    assert.equal((await pool.rankPoolBalance()).toString(), tokens(15));
    assert.equal((await pool.replenishPoolBalance()).toString(), tokens(30));
    assert.equal((await token.balanceOf(game.address)).toString(), "0");
    assert.equal(settlement.logs.find((log) => log.event === "SettlementModeSelected").args.usdtMode, false);
  });

  it("locks and refunds a three-player GoldenFlower room", async () => {
    const game = await GoldenFlower.new(token.address, dealer, pool.address, { from: owner });
    const deposit = tokens(300);
    await approveAndJoin(game, "joinRoom", 1, [player1, player2, player3], deposit);

    let room = await game.getRoomInfo(1);
    assert.equal(room.values[0].toString(), "1");
    assert.equal(room.values[6].toString(), "3");

    await game.refundRoom(1, { from: dealer });
    room = await game.getRoomInfo(1);
    assert.equal(room.values[0].toString(), "0");
    assert.equal(room.values[1].toString(), "2");
  });

  it("settles GoldenFlower in USDT mode when the settlement quote fits escrow", async () => {
    const game = await GoldenFlower.new(token.address, dealer, pool.address, { from: owner });
    const deposit = tokens(300);
    await approveAndJoin(game, "joinRoom", 1, [player1, player2, player3], deposit);

    await game.setQuoteBps(9_000, { from: owner });
    const settlement = await game.settleRoom(
      1,
      [player1, outsider, owner, dealer],
      [10_000, 10_000, 10_000, 0, 0, 1, 1, 900, 600],
      { from: dealer }
    );

    assert.equal((await pool.rankPoolBalance()).toString(), tokens(13.5));
    assert.equal((await pool.replenishPoolBalance()).toString(), tokens(27));
    assert.equal((await token.balanceOf(game.address)).toString(), tokens(90));
    assert.equal(settlement.logs.find((log) => log.event === "SettlementModeSelected").args.usdtMode, true);
  });
});
