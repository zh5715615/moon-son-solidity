const registry = require("../deployments/bsc-testnet-97.json");

console.log(`${registry.network.name} (Chain ID ${registry.network.chainId})`);
console.log("=".repeat(72));

for (const item of registry.deployments) {
  console.log(`${item.deployedAtAsiaShanghai}  ${item.contract}`);
  console.log(`  Address: ${item.address}`);
  console.log(`  Tx:      ${item.transactionHash}`);
  console.log(`  Block:   ${item.blockNumber}`);
}
