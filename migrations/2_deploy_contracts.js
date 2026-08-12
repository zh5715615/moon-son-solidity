const MockToken = artifacts.require("MockToken");
const GameRewardPool = artifacts.require("GameRewardPool");
const Landlords = artifacts.require("Landlords");
const GoldenFlower = artifacts.require("GoldenFlower");
const Bullfigthing = artifacts.require("Bullfigthing");

module.exports = async function (deployer, network, accounts) {
  const isLocal = network === "development" || network === "test";
  let tokenAddress = process.env.TOKEN_ADDRESS;

  if (!tokenAddress) {
    if (!isLocal) {
      throw new Error("TOKEN_ADDRESS is required for non-local deployments");
    }
    await deployer.deploy(MockToken);
    tokenAddress = MockToken.address;
  }

  const dealer = process.env.DEALER_ADDRESS || accounts[0];
  const bullOwner = process.env.BULL_OWNER_ADDRESS || accounts[0];

  await deployer.deploy(GameRewardPool, tokenAddress);
  const rewardPoolAddress = GameRewardPool.address;

  await deployer.deploy(Landlords, tokenAddress, dealer, rewardPoolAddress);
  await deployer.deploy(GoldenFlower, tokenAddress, dealer, rewardPoolAddress);
  await deployer.deploy(Bullfigthing, bullOwner, rewardPoolAddress, tokenAddress);

  console.log("Deployment summary:");
  console.log(`  Token:          ${tokenAddress}`);
  console.log(`  GameRewardPool: ${rewardPoolAddress}`);
  console.log(`  Landlords:      ${Landlords.address}`);
  console.log(`  GoldenFlower:   ${GoldenFlower.address}`);
  console.log(`  Bullfigthing:   ${Bullfigthing.address}`);
  console.log(`  Dealer:         ${dealer}`);
  console.log(`  Bull owner:     ${bullOwner}`);
};
