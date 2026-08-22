const GameRewardPool = artifacts.require("GameRewardPool");
const { recordDeployment } = require("./lib/record-deployment");

module.exports = async function (callback) {
  try {
    const accounts = await web3.eth.getAccounts();
    const deployer = accounts[0];
    const yion = process.env.YION_ADDRESS || process.env.TOKEN_ADDRESS;

    if (!yion) throw new Error("YION_ADDRESS is required");

    const balance = await web3.eth.getBalance(deployer);
    console.log(`Deploying GameRewardPool from ${deployer}`);
    console.log(`Deployer native balance: ${web3.utils.fromWei(balance, "ether")}`);
    console.log(`YION: ${yion}`);

    const instance = await GameRewardPool.new(yion, { from: deployer });
    console.log(`GameRewardPool deployed: ${instance.address}`);
    console.log(`Transaction hash: ${instance.transactionHash}`);
    await recordDeployment({
      web3,
      contract: "GameRewardPool",
      instance,
      deployer,
      constructorArguments: { yion },
    });
    callback();
  } catch (error) {
    callback(error);
  }
};
