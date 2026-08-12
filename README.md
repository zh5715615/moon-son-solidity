# 弈元游戏合约

本仓库是一个可重复编译、部署和测试的 Truffle 工程，包含斗地主、炸金花、牛牛以及共享游戏奖励池。

## 环境要求

- Node.js 18、20 或 22
- npm 9+

## 安装与验证

```bash
npm install
npm run compile
npm test
```

`npm test` 使用内存中的 Ganache，不需要单独启动节点。Solidity 编译器固定为项目依赖中的 `solc@0.8.21`，不会在构建时临时下载编译器。

## 本地部署

打开两个终端：

```bash
# 终端一
npm run ganache

# 终端二
npm run migrate:local
```

本地未配置 `TOKEN_ADDRESS` 时，迁移会自动部署 `MockToken`，随后依次部署奖励池和三个游戏合约。部署地址会打印到终端并写入 `build/contracts/*.json`。

## 钱包签名部署

复制 `.env.example` 为 `.env`，至少设置真实 ERC-20 地址：

```dotenv
TOKEN_ADDRESS=0x...
DEALER_ADDRESS=0x...
BULL_OWNER_ADDRESS=0x...
```

然后启动 Dashboard 并连接钱包：

```bash
npx truffle dashboard
npm run migrate:dashboard
```

非本地网络缺少 `TOKEN_ADDRESS` 时迁移会立即终止，防止把测试币误当成业务币。部署账户需要有足够的原生币支付 gas。代币必须实现 `decimals`、`balanceOf`、`allowance`、`approve`、`transfer` 和 `transferFrom`。

## 合约部署关系

1. `GameRewardPool(token)`
2. `Landlords(token, dealer, rewardPool)`
3. `GoldenFlower(token, dealer, rewardPool)`
4. `Bullfigthing(owner, rewardPool, token)`

部署后的 ABI 和网络地址位于 `build/contracts/`。`dealer` 负责斗地主和炸金花结算；`Bullfigthing` 的 owner 负责牛牛结算；奖励池 owner 负责登记用户可领取奖励。

## 常用命令

```bash
npm run compile          # 全量编译
npm test                 # 隔离网络执行测试
npm run migrate:local    # 重置并部署到本地 8545 节点
npm run deploy:bull:testnet # 单独部署 Bullfigthing 到配置的测试网
npm run console:local    # 打开 Truffle 控制台
```

`contracts/mocks/MockToken.sol` 只用于本地开发和测试，不应部署为生产业务代币。

## 部署记录与工程记忆

每次通过仓库的测试网部署脚本成功部署后，脚本会自动追加两份记录：

- `deployments/bsc-testnet-97.json`：包含完整地址、交易哈希、区块时间、部署账户和构造参数的机器可读历史。
- `DEPLOYMENTS.md`：带 BscScan 链接、便于人工查看的部署清单。

随时输出全部部署历史：

```bash
npm run deployments
```

换环境后先阅读 `PROJECT_MEMORY.md`。部署历史采用追加模式，重新部署不会覆盖旧地址。`.env`、私钥和 RPC 访问令牌不会写入工程记忆。
