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

## USDT 计价与 Token 支付

三个游戏合约的构造参数保持不变。房间配置金额使用两位小数的 USDT
美分整数，例如 `3000` 表示 `30.00 USDT`。玩家入房时，合约通过
PancakeSwap V2 的 Token/USDT 直连池调用 `getAmountsIn`，计算达到该
USDT 价值所需的业务 Token 数量，并实际托管业务 Token。

链上地址由 `block.chainid` 自动选择：

| Chain ID | 网络 | USDT | PancakeSwap V2 Router |
| ---: | --- | --- | --- |
| 56 | BSC Mainnet | `0x55d398326f99059fF775485246999027B3197955` | `0x10ED43C718714eb63d5aA57B78B54704E256024E` |
| 97 | BSC Testnet | `0x5B32Cc7d18643073BDB15dAfafC5C35E736c91a5` | `0xD99D1c33F9fC3444f8101754aBC46c52416550D1` |

前端入房流程：

1. 读取房间配置中的 USDT 美分价格。
2. 调用游戏合约 `quoteTokenAmount(usdtPriceCents)` 获取当前 Token 报价。
3. 只授权本次所需 Token 数量（可加入很小容差）。
4. 调用 `joinRoom` 或 `enterTheRoom`。

不要使用无限授权。PancakeSwap V2 储备现货报价可能在交易排序期间变化或被操纵；
精确/有限授权会作为用户支付上限，使异常报价交易回滚。报价使用直连池，目标链上
必须存在足够的 Token/USDT V2 流动性。

结算同样以 USDT 美分记账。斗地主和炸金花 `settleRoom` 中的玩家押注、赢家、
直推和间推金额均为 USDT 美分；牛牛根据房间 USDT 价格自动计算总额。三个游戏
都先对整局 USDT 托管总额报价一次，再按选定的 Token 结算总额计算退款与各项奖励，
确保模式判断与实际支付使用同一价格快照。

合约会先计算完整 U 结算所需的 Token。若该数量不超过本局实际托管 Token，
采用结算时 U 报价；若超过，则自动降级为 Token 比例模式，使用本局实际 Token
按同样的 70%/10%/10%/5%/3%/2% 规则分配。模式判断不会挪用其他房间资金。

`SettlementModeSelected` 事件记录 `usdtMode`、本局托管 Token、U 报价所需
Token 和最终支付 Token。U 模式下的多余 Token 留在游戏合约中，但不会被纳入
其他房间的模式判断。取消房间不使用新报价，原样退回玩家入房时托管的 Token。

部署后的 ABI 和网络地址位于 `build/contracts/`。`dealer` 负责斗地主和炸金花结算；`Bullfigthing` 的 owner 负责牛牛结算；奖励池 owner 负责登记用户可领取奖励。

## 常用命令

```bash
npm run compile          # 全量编译
npm test                 # 隔离网络执行测试
npm run migrate:local    # 重置并部署到本地 8545 节点
npm run deploy:bull:testnet # 单独部署 Bullfigthing 到配置的测试网
npm run deploy:yion:testnet # 部署固定总量 YION 并创建测试网 YION/USDT 池
npm run deploy:yion-ecosystem:testnet # 一键部署 YION、池、奖励池、三个游戏并最后激活
npm run console:local    # 打开 Truffle 控制台
```

## YION

`YION` 是 8 位精度、固定总量的 ERC-20。构造函数一次性向部署账户铸造
100,000,000 YION，合约没有后续增发入口。测试网部署脚本会在余额预检通过后，
将全部 YION 与 10,000 测试网 USDT 加入 PancakeSwap V2，初始比例为
`1 USDT = 10,000 YION`，LP Token 由部署账户持有。

流动性池激活后的前 30 分钟为白名单保护期：只有合约内写死的 100 个地址能通过
官方 YION/USDT Pair 买卖，单笔按 PancakeSwap 即时报价必须严格小于 200 USDT，
同时禁止普通地址转账和其他交易对绕过。保护期结束后自动开放所有地址和金额。

一键生态部署脚本严格按以下顺序执行：部署 YION、创建并注入 YION/USDT 池、部署
绑定 YION 的 `GameRewardPool`、依次部署 `Bullfigthing`、`GoldenFlower` 和
`Landlords`，最后调用 `activateTrading`。因此30分钟保护倒计时不会在奖励池和游戏
合约准备完成之前启动。`DEALER_ADDRESS`、`BULL_OWNER_ADDRESS` 未配置时均使用部署账户。

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
