const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..", "..");
const REGISTRY = path.join(ROOT, "deployments", "bsc-testnet-97.json");
const SUMMARY = path.join(ROOT, "DEPLOYMENTS.md");

function short(value) {
  return `${value.slice(0, 6)}…${value.slice(-4)}`;
}

function shanghaiTime(unixSeconds) {
  const parts = new Intl.DateTimeFormat("sv-SE", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(unixSeconds * 1000));
  const item = Object.fromEntries(parts.map(({ type, value }) => [type, value]));
  return `${item.year}-${item.month}-${item.day} ${item.hour}:${item.minute}:${item.second} +08:00`;
}

function renderSummary(registry) {
  const explorer = registry.network.explorer;
  const lines = [
    "# 合约部署记录",
    "",
    `网络：${registry.network.name}（Chain ID ${registry.network.chainId}）`,
    "",
    "> 本文件由部署登记工具自动生成。权威数据位于 `deployments/bsc-testnet-97.json`。",
    "",
    "| 部署时间（北京时间） | 合约 | 合约地址 | 部署交易 | 区块 | 部署账户 |",
    "| --- | --- | --- | --- | ---: | --- |",
  ];

  for (const item of registry.deployments) {
    lines.push(
      `| ${item.deployedAtAsiaShanghai} | ${item.contract} | ` +
      `[${short(item.address)}](${explorer}/address/${item.address}) | ` +
      `[${short(item.transactionHash)}](${explorer}/tx/${item.transactionHash}) | ` +
      `${item.blockNumber} | \`${short(item.deployer)}\` |`
    );
  }
  return `${lines.join("\n")}\n`;
}

async function recordDeployment({ web3, contract, instance, deployer, constructorArguments }) {
  const txHash = instance.transactionHash;
  const receipt = await web3.eth.getTransactionReceipt(txHash);
  if (!receipt || !receipt.status) {
    throw new Error(`Cannot record unsuccessful deployment transaction ${txHash}`);
  }
  const block = await web3.eth.getBlock(receipt.blockNumber);
  const timestamp = Number(block.timestamp);
  const registry = JSON.parse(fs.readFileSync(REGISTRY, "utf8"));

  if (registry.deployments.some((item) => item.transactionHash.toLowerCase() === txHash.toLowerCase())) {
    console.log(`Deployment already recorded: ${txHash}`);
    return;
  }

  registry.deployments.push({
    contract,
    address: instance.address,
    transactionHash: txHash,
    blockNumber: Number(receipt.blockNumber),
    blockTimestamp: timestamp,
    deployedAtUtc: new Date(timestamp * 1000).toISOString(),
    deployedAtAsiaShanghai: shanghaiTime(timestamp),
    deployer,
    constructorArguments,
    gasUsed: Number(receipt.gasUsed),
    status: "success",
  });

  fs.writeFileSync(REGISTRY, `${JSON.stringify(registry, null, 2)}\n`, "utf8");
  fs.writeFileSync(SUMMARY, renderSummary(registry), "utf8");
  console.log(`Deployment recorded in ${path.relative(ROOT, REGISTRY)}`);
}

module.exports = { recordDeployment };
