const Bullfigthing = artifacts.require("Bullfigthing");
const { recordDeployment } = require("./lib/record-deployment");

module.exports = async function (callback) {
  try {
    const accounts = await web3.eth.getAccounts();
    const deployer = accounts[0];
    const owner = process.env.BULL_OWNER_ADDRESS || deployer;
    const rewardPool = process.env.REWARD_POOL_ADDRESS;
    const token = process.env.TOKEN_ADDRESS;

    if (!rewardPool) throw new Error("REWARD_POOL_ADDRESS is required");
    if (!token) throw new Error("TOKEN_ADDRESS is required");

    const balance = await web3.eth.getBalance(deployer);
    console.log(`Deploying Bullfigthing from ${deployer}`);
    console.log(`Deployer native balance: ${web3.utils.fromWei(balance, "ether")}`);
    console.log(`Owner: ${owner}`);
    console.log(`Reward pool: ${rewardPool}`);
    console.log(`Token: ${token}`);

    const instance = await Bullfigthing.new(owner, rewardPool, token, { from: deployer });
    console.log(`Bullfigthing deployed: ${instance.address}`);
    console.log(`Transaction hash: ${instance.transactionHash}`);
    await recordDeployment({
      web3,
      contract: "Bullfigthing",
      instance,
      deployer,
      constructorArguments: { beneficiary: owner, rewardPool, token },
    });
    callback();
  } catch (error) {
    callback(error);
  }
};
