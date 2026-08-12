const Landlords = artifacts.require("Landlords");
const GoldenFlower = artifacts.require("GoldenFlower");
const Bullfigthing = artifacts.require("Bullfigthing");
const { recordDeployment } = require("./lib/record-deployment");

module.exports = async function (callback) {
  try {
    const accounts = await web3.eth.getAccounts();
    const deployer = accounts[0];
    const dealer = process.env.DEALER_ADDRESS || deployer;
    const bullOwner = process.env.BULL_OWNER_ADDRESS || deployer;
    const token = process.env.TOKEN_ADDRESS;
    const rewardPool = process.env.REWARD_POOL_ADDRESS;

    if (!token) throw new Error("TOKEN_ADDRESS is required");
    if (!rewardPool) throw new Error("REWARD_POOL_ADDRESS is required");

    const balance = await web3.eth.getBalance(deployer);
    console.log(`Deploying game contracts from ${deployer}`);
    console.log(`Deployer native balance: ${web3.utils.fromWei(balance, "ether")}`);
    console.log(`Dealer: ${dealer}`);
    console.log(`Bull owner: ${bullOwner}`);
    console.log(`Token: ${token}`);
    console.log(`Reward pool: ${rewardPool}`);

    const landlords = await Landlords.new(token, dealer, rewardPool, { from: deployer });
    console.log(`Landlords deployed: ${landlords.address}`);
    console.log(`Landlords transaction: ${landlords.transactionHash}`);
    await recordDeployment({
      web3,
      contract: "Landlords",
      instance: landlords,
      deployer,
      constructorArguments: { token, dealer, rewardPool },
    });

    const goldenFlower = await GoldenFlower.new(token, dealer, rewardPool, { from: deployer });
    console.log(`GoldenFlower deployed: ${goldenFlower.address}`);
    console.log(`GoldenFlower transaction: ${goldenFlower.transactionHash}`);
    await recordDeployment({
      web3,
      contract: "GoldenFlower",
      instance: goldenFlower,
      deployer,
      constructorArguments: { token, dealer, rewardPool },
    });

    const bullfigthing = await Bullfigthing.new(bullOwner, rewardPool, token, { from: deployer });
    console.log(`Bullfigthing deployed: ${bullfigthing.address}`);
    console.log(`Bullfigthing transaction: ${bullfigthing.transactionHash}`);
    await recordDeployment({
      web3,
      contract: "Bullfigthing",
      instance: bullfigthing,
      deployer,
      constructorArguments: { beneficiary: bullOwner, rewardPool, token },
    });
    callback();
  } catch (error) {
    callback(error);
  }
};
