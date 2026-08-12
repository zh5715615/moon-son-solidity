const GameRewardPool = artifacts.require("GameRewardPool");
const { recordDeployment } = require("./lib/record-deployment");

module.exports = async function (callback) {
  try {
    const accounts = await web3.eth.getAccounts();
    const deployer = accounts[0];
    const token = process.env.TOKEN_ADDRESS;

    if (!token) throw new Error("TOKEN_ADDRESS is required");

    const balance = await web3.eth.getBalance(deployer);
    console.log(`Deploying GameRewardPool from ${deployer}`);
    console.log(`Deployer native balance: ${web3.utils.fromWei(balance, "ether")}`);
    console.log(`Token: ${token}`);

    const instance = await GameRewardPool.new(token, { from: deployer });
    console.log(`GameRewardPool deployed: ${instance.address}`);
    console.log(`Transaction hash: ${instance.transactionHash}`);
    await recordDeployment({
      web3,
      contract: "GameRewardPool",
      instance,
      deployer,
      constructorArguments: { token },
    });
    callback();
  } catch (error) {
    callback(error);
  }
};
