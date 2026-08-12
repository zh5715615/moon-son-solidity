const Bullfigthing = artifacts.require("Bullfigthing");
const MockToken = artifacts.require("MockToken");

module.exports = async function (callback) {
  try {
    const [account] = await web3.eth.getAccounts();
    const bull = await Bullfigthing.at(process.env.BULLFIGTHING_ADDRESS);
    const token = await MockToken.at(process.env.TOKEN_ADDRESS);
    const usdtPriceCents = 3000;
    const quotedTokenAmount = await bull.quoteTokenAmount(usdtPriceCents);

    console.log(`Account: ${account}`);
    console.log(`Bullfigthing: ${bull.address}`);
    console.log(`USDT price cents: ${usdtPriceCents}`);
    console.log(`Quoted token amount (raw): ${quotedTokenAmount.toString()}`);

    const approval = await token.approve(bull.address, quotedTokenAmount, { from: account });
    console.log(`Approval transaction: ${approval.tx}`);

    const entry = await bull.enterTheRoom(0, { from: account });
    console.log(`Entry transaction: ${entry.tx}`);

    const userRoom = await bull.getUserRoom(account);
    const player = await bull.getPlayerInfo(0, account);
    console.log(`Joined: ${userRoom.joined}`);
    console.log(`Room level: ${userRoom.level.toString()}`);
    console.log(`Recorded token amount (raw): ${player.values[0].toString()}`);
    callback();
  } catch (error) {
    callback(error);
  }
};
