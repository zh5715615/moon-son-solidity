const Bullfigthing = artifacts.require("Bullfigthing");
const { recordDeployment } = require("./lib/record-deployment");

module.exports = async function (callback) {
  try {
    const accounts = await web3.eth.getAccounts();
    const deployer = accounts[0];
    const owner = process.env.BULL_OWNER_ADDRESS || deployer;
    const rewardPool = process.env.REWARD_POOL_ADDRESS;
    const yion = process.env.YION_ADDRESS || process.env.TOKEN_ADDRESS;

    if (!rewardPool) throw new Error("REWARD_POOL_ADDRESS is required");
    if (!yion) throw new Error("YION_ADDRESS is required");

    const balance = await web3.eth.getBalance(deployer);
    console.log(`Deploying Bullfigthing from ${deployer}`);
    console.log(`Deployer native balance: ${web3.utils.fromWei(balance, "ether")}`);
    console.log(`Owner: ${owner}`);
    console.log(`Reward pool: ${rewardPool}`);
    console.log(`YION: ${yion}`);

    const instance = await Bullfigthing.new(owner, rewardPool, yion, { from: deployer });
    console.log(`Bullfigthing deployed: ${instance.address}`);
    console.log(`Transaction hash: ${instance.transactionHash}`);
    await recordDeployment({
      web3,
      contract: "Bullfigthing",
      instance,
      deployer,
      constructorArguments: { beneficiary: owner, rewardPool, yion },
    });
    callback();
  } catch (error) {
    callback(error);
  }
};
