const YION = artifacts.require("YION");

const ERC20_ABI = [
  { constant: true, inputs: [{ name: "account", type: "address" }], name: "balanceOf", outputs: [{ name: "", type: "uint256" }], type: "function" },
];

const PAIR_ABI = [
  ...ERC20_ABI,
  { constant: true, inputs: [], name: "token0", outputs: [{ name: "", type: "address" }], type: "function" },
  { constant: true, inputs: [], name: "token1", outputs: [{ name: "", type: "address" }], type: "function" },
  { constant: true, inputs: [], name: "getReserves", outputs: [{ name: "reserve0", type: "uint112" }, { name: "reserve1", type: "uint112" }, { name: "blockTimestampLast", type: "uint32" }], type: "function" },
];

module.exports = async function (callback) {
  try {
    const [deployer] = await web3.eth.getAccounts();
    const yion = await YION.at(process.env.YION_ADDRESS);
    const pair = new web3.eth.Contract(PAIR_ABI, process.env.YION_USDT_PAIR);
    const token0 = await pair.methods.token0().call();
    const token1 = await pair.methods.token1().call();
    const reserves = await pair.methods.getReserves().call();
    const reserveByToken = {
      [token0.toLowerCase()]: reserves.reserve0,
      [token1.toLowerCase()]: reserves.reserve1,
    };

    console.log(JSON.stringify({
      yion: {
        address: yion.address,
        code: (await web3.eth.getCode(yion.address)).length > 2,
        name: await yion.name(),
        symbol: await yion.symbol(),
        decimals: Number(await yion.decimals()),
        totalSupply: (await yion.totalSupply()).toString(),
        pairBalance: (await yion.balanceOf(pair.options.address)).toString(),
        deployerBalance: (await yion.balanceOf(deployer)).toString(),
        configuredPair: await yion.liquidityPair(),
        restrictionActive: await yion.restrictionActive(),
        restrictedUntil: (await yion.restrictedUntil()).toString(),
        firstWhitelistAddressEnabled: await yion.whitelist("0xD9F200aFF52895F1bdd221a883071E8BA94C30D0"),
        lastWhitelistAddressEnabled: await yion.whitelist("0xFb5a610E6B06E52d5a3f2f7A23185Aa965cfE376"),
      },
      pair: {
        address: pair.options.address,
        code: (await web3.eth.getCode(pair.options.address)).length > 2,
        yionReserve: reserveByToken[yion.address.toLowerCase()],
        usdtReserve: reserveByToken[process.env.YION_USDT_ADDRESS.toLowerCase()],
        lpBalanceOfDeployer: await pair.methods.balanceOf(deployer).call(),
      },
    }, null, 2));
    callback();
  } catch (error) {
    callback(error);
  }
};
