const MockToken = artifacts.require("MockToken");
const GameRewardPool = artifacts.require("GameRewardPool");
const Bullfigthing = artifacts.require("Bullfigthing");

contract("Bullfigthing", (accounts) => {
  const [owner, winner, player2, player3, player4, player5] = accounts;
  const players = [winner, player2, player3, player4, player5];
  const tokens = (value) => web3.utils.toWei(String(value), "ether");

  it("settles a full room and funds both reward pools", async () => {
    const token = await MockToken.new({ from: owner });
    const pool = await GameRewardPool.new(token.address, { from: owner });
    const game = await Bullfigthing.new(owner, pool.address, token.address, { from: owner });
    const roomDeposit = tokens(3_000);

    for (const player of players) {
      await token.mint(player, roomDeposit, { from: owner });
      await token.approve(game.address, roomDeposit, { from: player });
      await game.enterTheRoom(0, { from: player });
    }

    const beforeWinner = await token.balanceOf(winner);
    await game.sendInstantReward(0, winner, [], [], { from: owner });
    const total = web3.utils.toBN(roomDeposit).mul(web3.utils.toBN(5));
    const expectedWinner = total.mul(web3.utils.toBN(70)).div(web3.utils.toBN(100));
    const afterWinner = await token.balanceOf(winner);

    assert.equal(afterWinner.sub(beforeWinner).toString(), expectedWinner.toString());
    assert.equal((await pool.rankPoolBalance()).toString(), total.muln(5).divn(100).toString());
    assert.equal((await pool.replenishPoolBalance()).toString(), total.muln(10).divn(100).toString());
    const room = await game.getRoomInfo(0);
    assert.equal(room.values[2].toString(), "0");
    assert.equal(room.values[3].toString(), "1");
    assert.equal(room.values[4].toString(), "2");
  });
});
