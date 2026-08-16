# 弈元游戏 Solidity 合约

这是一个基于 Truffle 的 BSC 游戏合约工程，包含：

- 固定发行量的 `YION` ERC-20
- PancakeSwap V2 `YION/USDT` 初始流动性池
- 共享奖励池 `GameRewardPool`
- 斗牛 `Bullfigthing`
- 炸金花 `GoldenFlower`
- 斗地主 `Landlords`

本文档覆盖环境配置、安装、编译、测试、本地调试、测试网部署、部署后验证和常见问题。

## 1. 环境要求

推荐环境：

| 工具 | 推荐版本 | 说明 |
| --- | --- | --- |
| Node.js | 20 LTS | 项目提供 `.nvmrc`；避免 Node 22 的 µWS ABI 警告 |
| npm | 9 或 10 | 使用 `package-lock.json` 锁定依赖 |
| Solidity | 0.8.21 | 使用项目内 `node_modules/solc/soljson.js` |
| Truffle | 5.11.5 | 已包含在开发依赖中 |

使用 nvm：

```bash
nvm install 20
nvm use
node -v
npm -v
```

Node 18 也可以使用。Node 22 通常仍能运行，但 Ganache 会输出 µWS 原生模块不兼容警告并回退到 JavaScript 实现。

## 2. 安装依赖

新环境或服务器推荐使用：

```bash
npm ci
```

需要修改依赖时使用：

```bash
npm install
```

不要提交 `node_modules/`、`.env`、私钥、助记词或带访问令牌的 RPC URL。

## 3. 环境变量配置

复制配置模板：

```bash
cp .env.example .env
```

Windows PowerShell：

```powershell
Copy-Item .env.example .env
```

`.env` 示例：

```dotenv
# 已存在的业务 Token；单独部署奖励池或游戏合约时使用。
TOKEN_ADDRESS=0x...

# 已存在的奖励池；单独部署游戏合约时使用。
REWARD_POOL_ADDRESS=0x...

# BSC 测试网 RPC 和部署私钥。
TESTNET_RPC_URL=https://...
DEPLOYER_PRIVATE_KEY=...

# 可选。不配置时默认使用部署账户。
DEALER_ADDRESS=0x...
BULL_OWNER_ADDRESS=0x...

# 本地 development 网络。
RPC_HOST=127.0.0.1
RPC_PORT=8545
NETWORK_ID=*
```

变量说明：

| 变量 | 必填场景 | 用途 |
| --- | --- | --- |
| `TESTNET_RPC_URL` | 所有 BSC 测试网部署 | BSC Testnet RPC |
| `DEPLOYER_PRIVATE_KEY` | 所有 BSC 测试网部署 | 支付 gas 和签名交易 |
| `TOKEN_ADDRESS` | 单独部署奖励池/游戏 | 指定已有 ERC-20 |
| `REWARD_POOL_ADDRESS` | 单独部署游戏 | 指定已有奖励池 |
| `DEALER_ADDRESS` | 可选 | 斗地主、炸金花结算账户 |
| `BULL_OWNER_ADDRESS` | 可选 | 斗牛 owner |
| `RPC_HOST/RPC_PORT/NETWORK_ID` | 本地外部 Ganache | 本地 RPC 配置 |

一键部署 YION 生态不读取 `TOKEN_ADDRESS` 和 `REWARD_POOL_ADDRESS`，它会创建新的 YION 和奖励池，并把新地址自动传给三个游戏合约。

## 4. 编译

全量编译：

```bash
npm run compile
```

编译产物位于：

```text
build/contracts/*.json
```

每个 JSON 包含 ABI、bytecode 和网络部署信息。远程部署命令均配置了 npm 前置脚本，会自动先执行全量编译。

如果直接运行 `truffle exec`，必须先手动执行 `npm run compile`，否则会出现：

```text
ENOENT: no such file or directory, scandir '.../build/contracts'
```

## 5. 自动化测试

运行全部测试：

```bash
npm test
```

测试使用内存 Ganache，不需要启动外部节点。`--migrate-none` 已写入 npm 命令，避免 `.env` 中的远程地址被本地迁移误用。

运行单个测试文件：

```bash
npx truffle test test/yion.test.js --network test --migrate-none
npx truffle test test/roomEscrow.test.js --network test --migrate-none
npx truffle test test/bullfigthing.test.js --network test --migrate-none
npx truffle test test/gameRewardPool.test.js --network test --migrate-none
```

当前测试覆盖：

- YION 固定1亿发行量和8位精度
- 100个硬编码白名单地址
- 激活后30分钟白名单限制
- 单笔 `< 200 USDT`，等于200 USDT时拒绝
- 30分钟后自动开放交易和普通转账
- 三个游戏的入房、退款、涨价/跌价结算模式
- 奖励池存入、登记和用户领取

## 6. 本地链调试

### 6.1 启动本地 Ganache

终端一：

```bash
npm run ganache
```

默认监听：

```text
http://127.0.0.1:8545
networkId: 5777
```

### 6.2 本地迁移

终端二：

```bash
npm run migrate:local
```

如果希望本地自动部署 `MockToken`，请确保 `.env` 中的 `TOKEN_ADDRESS` 为空或被注释。迁移顺序为：

1. `MockToken`（仅本地且未配置 `TOKEN_ADDRESS` 时）
2. `GameRewardPool`
3. `Landlords`
4. `GoldenFlower`
5. `Bullfigthing`

本地迁移使用的是普通测试 Token，不会自动创建 PancakeSwap 流动性池。涉及实时报价的逻辑应优先使用测试目录中的 Pricing Harness 进行自动化测试。

### 6.3 Truffle 控制台

```bash
npm run console:local
```

示例：

```javascript
const game = await Landlords.deployed()
await game.getRoomInfo(1)
```

## 7. BSC 测试网配置

工程当前支持：

| 项目 | 值 |
| --- | --- |
| 网络 | BNB Smart Chain Testnet |
| Chain ID | 97 |
| 区块浏览器 | https://testnet.bscscan.com |
| 测试网 USDT | `0x5B32Cc7d18643073BDB15dAfafC5C35E736c91a5` |
| PancakeSwap V2 Router | `0xD99D1c33F9fC3444f8101754aBC46c52416550D1` |

部署账户必须持有足够的测试网 BNB。YION 生态一键部署还要求至少有10,000测试网 USDT，脚本要求 BNB 余额不低于0.2。

## 8. 一键部署完整 YION 生态

推荐命令：

```bash
npm run deploy:yion-ecosystem:testnet
```

npm 会先自动执行 `npm run compile`，再按以下顺序发送交易：

1. 创建 `YION`
2. 授权并创建 `YION/USDT` 流动性池，注入1亿 YION + 10,000 USDT
3. 创建以新 YION 为 Token 的 `GameRewardPool`
4. 创建以新 YION 和新奖励池为参数的 `Bullfigthing`
5. 创建以新 YION 和新奖励池为参数的 `GoldenFlower`
6. 创建以新 YION 和新奖励池为参数的 `Landlords`
7. 调用 `YION.activateTrading(pair)`，启动30分钟白名单期

虽然叫“一键部署”，但它不是一笔原子交易，而是一条包含多笔链上交易的自动流程。每笔成功部署都会立即写入部署登记。若中途失败，不要直接重复执行，否则会再次创建新的 Token、Pair 或游戏合约；应先检查终端输出和 `deployments/bsc-testnet-97.json`，确认失败发生在哪一步。

### 8.1 只读预检

Linux/macOS：

```bash
YION_ECOSYSTEM_PREFLIGHT_ONLY=true npm run deploy:yion-ecosystem:testnet
```

Windows PowerShell：

```powershell
$env:YION_ECOSYSTEM_PREFLIGHT_ONLY = "true"
npm run deploy:yion-ecosystem:testnet
Remove-Item Env:YION_ECOSYSTEM_PREFLIGHT_ONLY
```

预检会验证网络、部署账户、BNB 和 USDT 余额，但不会提交任何交易。

### 8.2 YION 参数

- 名称/符号：`YION` / `YION`
- decimals：8
- 固定总量：100,000,000
- 无后续增发入口
- 初始池：100,000,000 YION + 10,000 USDT
- 初始比例：`1 USDT = 10,000 YION`
- LP Token：发送给部署账户
- 白名单：100个地址，硬编码在 `contracts/YION.sol`

### 8.3 激活前后状态

| 阶段 | 状态 |
| --- | --- |
| 激活前 | 普通用户不能交易或转账；部署账户可以完成首次加池 |
| 激活后前30分钟 | 仅100个白名单地址可通过官方 Pair 买卖；单笔严格小于200 USDT；禁止普通转账和其他 Pair 绕过 |
| 30分钟后 | 所有地址可交易和转账，不再限制金额和 Pair |

`activateTrading` 只能由部署账户成功调用一次，官方 Pair 设置后不能修改，30分钟限制不能重启或延长。

## 9. 分步部署

分步命令同样会自动先编译。

### 9.1 仅部署 YION 并创建流动性池

```bash
npm run deploy:yion:testnet
```

该脚本会在加池后立即激活交易，不会部署奖励池和游戏合约。

### 9.2 单独部署奖励池

`.env` 必须配置：

```dotenv
TOKEN_ADDRESS=0x...
```

执行：

```bash
npm run deploy:pool:testnet
```

### 9.3 单独部署三个游戏

`.env` 必须配置：

```dotenv
TOKEN_ADDRESS=0x...
REWARD_POOL_ADDRESS=0x...
DEALER_ADDRESS=0x...
BULL_OWNER_ADDRESS=0x...
```

执行：

```bash
npm run deploy:games:testnet
```

### 9.4 仅部署斗牛

```bash
npm run deploy:bull:testnet
```

需要 `TOKEN_ADDRESS` 和 `REWARD_POOL_ADDRESS`；`BULL_OWNER_ADDRESS` 可选。

## 10. 部署关系与权限

构造关系：

```text
YION
├── PancakeSwap V2 YION/USDT Pair
└── GameRewardPool(YION)
    ├── Bullfigthing(owner, rewardPool, YION)
    ├── GoldenFlower(YION, dealer, rewardPool)
    └── Landlords(YION, dealer, rewardPool)
```

权限说明：

- `YION.launcher`：只能执行一次 `activateTrading`
- `GameRewardPool.owner`：登记排名奖励和权益回补奖励
- `Bullfigthing.owner`：执行斗牛结算、修改奖励池地址
- `GoldenFlower.dealer`：执行炸金花结算和退款
- `Landlords.dealer`：执行斗地主结算和退款

## 11. 游戏计价与结算

房间金额使用 USDT 美分整数，例如 `3000` 表示 `30.00 USDT`。玩家进入房间时，游戏合约通过 PancakeSwap V2 的 YION/USDT 直连池调用 `getAmountsIn`，计算并托管所需 YION。

前端入房流程：

1. 读取房间 USDT 美分价格。
2. 调用游戏合约 `quoteTokenAmount(usdtPriceCents)`。
3. 对游戏合约授权本次所需 YION，避免无限授权。
4. 斗地主/炸金花调用 `joinRoom`；斗牛调用 `enterTheRoom`。

结算时对整局 USDT 托管总额统一报价：

- 当前 USDT 等值 YION 不超过本房间托管额：按当前报价结算。
- 当前 USDT 等值 YION 超过本房间托管额：按本房间实际托管 YION 比例结算。
- 不会挪用其他房间余额。
- 取消房间时原样退回玩家入房时托管的 Token，不重新报价。

`SettlementModeSelected` 事件包含：

- `usdtMode`
- 本局托管 Token
- 当前报价所需 Token
- 最终支付 Token

## 12. 部署记录

所有仓库部署脚本都通过 `scripts/lib/record-deployment.js` 记录成功交易：

- `deployments/bsc-testnet-97.json`：权威机器可读记录
- `DEPLOYMENTS.md`：带 BscScan 链接的人工清单
- `PROJECT_MEMORY.md`：当前工程约定和最新地址摘要

查看历史：

```bash
npm run deployments
```

历史记录采用追加模式，重新部署不会覆盖旧地址。判断“当前使用哪个版本”时优先读取 `PROJECT_MEMORY.md`，完整交易事实以 JSON 登记为准。

## 13. 部署后验证

### 13.1 验证三个游戏配置

Linux/macOS：

```bash
LANDLORDS_ADDRESS=0x... \
GOLDEN_FLOWER_ADDRESS=0x... \
BULLFIGTHING_ADDRESS=0x... \
npx truffle exec scripts/verify-game-contracts.js --network bscTestnet
```

验证内容包括合约代码、Token、奖励池、dealer 和 owner。

### 13.2 验证 YION 和流动性池

```bash
YION_ADDRESS=0x... \
YION_USDT_PAIR=0x... \
YION_USDT_ADDRESS=0x5B32Cc7d18643073BDB15dAfafC5C35E736c91a5 \
npx truffle exec scripts/verify-yion-liquidity.js --network bscTestnet
```

验证内容包括名称、精度、总量、Pair 储备、部署账户余额、LP 余额、官方 Pair、白名单抽查和限制截止时间。

## 14. 常见问题

### 14.1 `build/contracts` 不存在

执行：

```bash
npm run compile
```

使用本仓库的 npm 部署命令时会自动编译；只有直接运行 `truffle exec` 时需要手动编译。

### 14.2 µWS 与 Node ABI 不兼容

典型输出：

```text
This version of µWS is not compatible with your Node.js build
Falling back to a NodeJS implementation
```

这是性能回退警告，不是部署失败。推荐切换 Node 20 并重装依赖：

```bash
nvm install 20
nvm use 20
rm -rf node_modules
npm ci
```

### 14.3 `TESTNET_RPC_URL is required`

检查 `.env` 是否位于项目根目录，变量名是否正确，并确认等号后有值。

### 14.4 `DEPLOYER_PRIVATE_KEY is required`

在 `.env` 中配置部署私钥。不要把私钥粘贴到聊天、README、部署记录或 Git 中。

### 14.5 USDT 或 BNB 余额不足

一键脚本会在部署 YION 前检查余额。至少需要：

- 10,000 测试网 USDT
- 0.2 测试网 BNB

### 14.6 PancakeSwap 报价失败

确认：

- Chain ID 是56或97
- Token/USDT 直连 Pair 存在
- Pair 有足够流动性
- 游戏合约绑定的 Token 地址与 Pair 中的 Token 一致

### 14.7 一键部署中途失败

先检查：

```bash
npm run deployments
```

再查看 `deployments/bsc-testnet-97.json` 和失败前终端输出。已经成功的交易无法回滚，不要直接重跑整个脚本。应根据最后成功步骤选择分步脚本或编写恢复脚本。

## 15. 安全注意事项

- 永远不要提交 `.env`、私钥、助记词或 RPC Token。
- 部署前先运行 `npm test` 和只读预检。
- 确认目标网络和 Chain ID，测试网资产与主网资产不可混用。
- 不要给前端或游戏合约无限 Token 授权。
- PancakeSwap V2 使用现货储备报价，价格可能被交易顺序或流动性变化影响。
- LP Token 当前发送给部署账户；是否锁仓、销毁或托管属于额外操作，本脚本不会自动执行。
- `contracts/mocks/` 仅用于本地测试，不能作为生产业务合约部署。
