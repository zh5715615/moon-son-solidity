const Landlords = artifacts.require("Landlords");
const GoldenFlower = artifacts.require("GoldenFlower");
const Bullfigthing = artifacts.require("Bullfigthing");

module.exports = async function (callback) {
  try {
    const landlords = await Landlords.at(process.env.LANDLORDS_ADDRESS);
    const goldenFlower = await GoldenFlower.at(process.env.GOLDEN_FLOWER_ADDRESS);
    const bullfigthing = await Bullfigthing.at(process.env.BULLFIGTHING_ADDRESS);

    const checks = {
      landlords: {
        code: (await web3.eth.getCode(landlords.address)).length > 2,
        yion: await landlords.yion(),
        dealer: await landlords.dealer(),
        rewardPool: await landlords.rewardPool(),
      },
      goldenFlower: {
        code: (await web3.eth.getCode(goldenFlower.address)).length > 2,
        yion: await goldenFlower.yion(),
        dealer: await goldenFlower.dealer(),
        rewardPool: await goldenFlower.rewardPool(),
      },
      bullfigthing: {
        code: (await web3.eth.getCode(bullfigthing.address)).length > 2,
        owner: await bullfigthing.owner(),
        yion: await bullfigthing.yionAddress(),
        rewardPool: await bullfigthing.gameRewardPoolAddress(),
      },
    };

    console.log(JSON.stringify(checks, null, 2));
    callback();
  } catch (error) {
    callback(error);
  }
};
