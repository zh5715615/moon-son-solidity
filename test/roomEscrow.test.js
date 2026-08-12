const MockToken = artifacts.require("MockToken");
const GameRewardPool = artifacts.require("GameRewardPool");
const Landlords = artifacts.require("Landlords");
const GoldenFlower = artifacts.require("GoldenFlower");
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
    const deposit = tokens(20_000);
    await approveAndJoin(game, "joinRoom", 1, [player1, player2, player3], deposit);

    let room = await game.getRoomInfo(1);
    assert.equal(room.values[0].toString(), "1", "room should be locked");
    assert.equal(room.values[3].toString(), "3");
    await expectRevert(game.refundRoom(1, { from: outsider }));

    await game.refundRoom(1, { from: dealer });
    room = await game.getRoomInfo(1);
    assert.equal(room.values[0].toString(), "0");
    assert.equal(room.values[1].toString(), "2");
    assert.equal((await token.balanceOf(player1)).toString(), tokens(200_000));
  });

  it("locks and refunds a three-player GoldenFlower room", async () => {
    const game = await GoldenFlower.new(token.address, dealer, pool.address, { from: owner });
    const deposit = tokens(30_000);
    await approveAndJoin(game, "joinRoom", 1, [player1, player2, player3], deposit);

    let room = await game.getRoomInfo(1);
    assert.equal(room.values[0].toString(), "1");
    assert.equal(room.values[6].toString(), "3");

    await game.refundRoom(1, { from: dealer });
    room = await game.getRoomInfo(1);
    assert.equal(room.values[0].toString(), "0");
    assert.equal(room.values[1].toString(), "2");
  });
});
