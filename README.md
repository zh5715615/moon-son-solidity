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
# 已存在的 YION；单独部署奖励池或游戏合约时使用。
YION_ADDRESS=0x...

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
| `YION_ADDRESS` | 单独部署奖励池/游戏 | 指定已有 YION；兼容旧变量 `TOKEN_ADDRESS` |
| `REWARD_POOL_ADDRESS` | 单独部署游戏 | 指定已有奖励池 |
| `DEALER_ADDRESS` | 可选 | 斗地主、炸金花结算账户 |
| `BULL_OWNER_ADDRESS` | 可选 | 斗牛 owner |
| `RPC_HOST/RPC_PORT/NETWORK_ID` | 本地外部 Ganache | 本地 RPC 配置 |

YION 生态部署脚本使用交互向导，分别询问是否部署 YION、奖励池和三个游戏合约。选择不部署时，会复用 `deployments/bsc-testnet-97.json` 中最近一次成功部署且依赖匹配的地址；详见第8节。

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

如果希望本地自动部署 `MockToken`，请确保 `.env` 中的 `YION_ADDRESS` 为空或被注释。迁移顺序为：

1. `MockToken`（仅本地且未配置 `YION_ADDRESS` 时）
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

部署账户必须持有足够的测试网 BNB。只有选择部署新 YION 时才要求至少有10,000测试网 USDT，并要求 BNB 余额不低于0.2；仅部署部分合约时按每个合约预留0.04 BNB。

## 8. YION 生态部署向导

推荐命令：

```bash
npm run deploy:yion-ecosystem:testnet
```

npm 会先自动执行 `npm run compile`，然后依次询问是否部署以下5个合约：

1. `YION`
2. 奖励合约 `GameRewardPool`
3. 斗牛合约 `Bullfigthing`
4. 炸金花合约 `GoldenFlower`
5. 斗地主合约 `Landlords`

每次提示输入 `y` 部署新合约；输入 `n` 或直接回车，则使用 `deployments/bsc-testnet-97.json` 中该合约最近一次成功部署的地址。复用地址会先检查链上代码和构造参数依赖。

如果选择部署新 YION，脚本还会自动创建新的 `YION/USDT` 流动性池，并在其他合约处理完成后激活交易。复用旧 YION 时则复用其最近一次登记的 Pair，不会重复添加流动性或重复激活。

依赖约束：

- 新 YION 必须同时部署新奖励池和三个游戏合约。
- 新奖励池必须同时部署三个游戏合约。
- 复用奖励池或游戏时，其登记的 YION、奖励池必须和本次选择一致，否则脚本在发送交易前终止。

虽然叫“一键部署”，但它不是一笔原子交易，而是一条包含多笔链上交易的自动流程。每笔成功部署都会立即写入部署登记。若中途失败，不要直接重复执行，否则会再次创建新的 Token、Pair 或游戏合约；应先检查终端输出和 `deployments/bsc-testnet-97.json`，确认失败发生在哪一步。

### 8.1 非交互选择

服务器或 CI 可以通过环境变量跳过问答：

| 合约 | 环境变量 |
| --- | --- |
| YION | `DEPLOY_YION` |
| GameRewardPool | `DEPLOY_REWARD_POOL` |
| Bullfigthing | `DEPLOY_BULLFIGTHING` |
| GoldenFlower | `DEPLOY_GOLDEN_FLOWER` |
| Landlords | `DEPLOY_LANDLORDS` |

变量支持 `true/false`、`yes/no`、`y/n` 或 `1/0`。例如只重新部署三个游戏：

```powershell
$env:DEPLOY_YION = "false"
$env:DEPLOY_REWARD_POOL = "false"
$env:DEPLOY_BULLFIGTHING = "true"
$env:DEPLOY_GOLDEN_FLOWER = "true"
$env:DEPLOY_LANDLORDS = "true"
npm run deploy:yion-ecosystem:testnet
```

### 8.2 只读预检

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

预检仍会显示5次选择提示，并验证网络、部署账户、复用地址、依赖关系、BNB，以及需要新建 YION 时的 USDT 余额，但不会提交任何交易。

### 8.3 YION 参数

- 名称/符号：`YION` / `YION`
- decimals：8
- 固定总量：100,000,000
- 无后续增发入口
- 初始池：100,000,000 YION + 10,000 USDT
- 初始比例：`1 USDT = 10,000 YION`
- LP Token：发送给部署账户
- 白名单：100个地址，硬编码在 `contracts/YION.sol`
- 单笔限制：构造时读取 USDT `decimals()`，换算成 `200 USDT` 的原始单位；允许正好200 USDT，只有大于200 USDT才拒绝
- 买入手续费：官方 Pair 输出的 YION 中扣3%，用户实际收到97%，手续费 YION 直接发送到手续费地址
- 卖出手续费：用户卖出的 YION 中扣3%，官方 Pair 实际收到97%，手续费 YION 直接发送到手续费地址
- 手续费收款地址：`0xa24bDb249e80574A96D8B02b148E81B9be684675`
- 免手续费白名单：`feeExempt` 与前30分钟交易白名单相互独立；部署账户和 Token 合约自身默认免手续费，部署账户可通过 `setFeeExempt` 增删地址

### 8.4 激活前后状态

| 阶段 | 状态 |
| --- | --- |
| 激活前 | 普通用户不能交易或转账；部署账户可以完成首次加池 |
| 激活后前30分钟 | 仅100个交易白名单地址可通过官方 Pair 买卖；单笔严格小于200 USDT；禁止普通转账 |
| 30分钟后 | 所有地址均可通过官方 Pair 买卖，不再限制金额；普通转账恢复 |

`activateTrading` 只能由部署账户成功调用一次，官方 Pair 设置后不能修改，30分钟限制不能重启或延长。

交易者可以直接使用 PancakeSwap V2 页面或 Router 买卖。买入时输入的 USDT 全部进入 AMM，Pair 输出的 YION 由 Token 合约拆成97%给用户、3%给手续费地址；卖出时用户提交的 YION 拆成97%进入 Pair、3%给手续费地址。前端必须使用支持 Fee-on-Transfer Token 的买卖接口，尤其卖出应调用 `swapExactTokensForTokensSupportingFeeOnTransferTokens`。

手续费直接以 YION 支付给固定手续费地址，不经过 Token 合约累计，也不执行自动换币，因此每笔交易只有一次简单的手续费拆分。

`setFeeExempt(account, true/false)` 管理独立的免手续费白名单，不影响前30分钟交易资格。部署账户和 YION Token 合约地址自身默认在该白名单中；官方 Pair 不应加入免手续费白名单。

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
YION_ADDRESS=0x...
```

执行：

```bash
npm run deploy:pool:testnet
```

### 9.3 单独部署三个游戏

`.env` 必须配置：

```dotenv
YION_ADDRESS=0x...
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

需要 `YION_ADDRESS` 和 `REWARD_POOL_ADDRESS`；`BULL_OWNER_ADDRESS` 可选。

### 9.5 买入并分发1,000,000 YION

该脚本只允许 `.env` 中私钥对应的签名账户为
`0x7c92cd77d3fbA3ea33f7D94254bf3E23B25513C2`。它会从部署登记中读取最新的
YION、Pair 和 Router，按 PancakeSwap 实时报价精确买入总计1,000,000 YION，
然后向代码内配置的4个地址各发送250,000 YION。

先执行只读报价和余额检查：

```powershell
$env:YION_DISTRIBUTION_DRY_RUN = "true"
npm run buy-distribute:yion:testnet
```

确认报价后执行真实交易：

```powershell
$env:YION_DISTRIBUTION_DRY_RUN = "false"
npm run buy-distribute:yion:testnet
```

脚本显示最终报价后，输入 `yes` 即可执行（不区分大小写）。自动化环境可以设置
`CONFIRM_YION_DISTRIBUTION=true` 跳过人工确认。默认允许2%价格滑点，可通过
`YION_BUY_SLIPPAGE_BPS` 调整，例如 `200` 表示2%。

执行顺序为：必要时授权 USDT、精确买入 YION、依次发送4笔 YION。脚本会拒绝
错误签名账户、错误 Pair/Router、余额不足，以及仍处于激活后30分钟限制期的 YION。

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

房间金额使用 USDT 美分整数，例如 `500` 表示 `5.00 USDT`，`200` 表示 `2.00 USDT`。玩家进入房间时，游戏合约通过 PancakeSwap V2 的 YION/USDT 直连池调用 `getAmountsOut`，按“输入 USDT、输出 YION”的买入方向计算并托管 YION，与 PancakeSwap 买入页面的 Router 报价口径一致。

当前源码房间配置：

| 游戏 | 房间数量 | 单人入场费 | 房间人数 |
| --- | ---: | ---: | --- |
| 斗牛 | 15 | 5 USDT | 5 人 |
| 炸金花 | 20 | 3 人房 2 USDT；5 人房 4 USDT | 1-10 为 3 人，11-20 为 5 人 |
| 斗地主 | 12 | 2 USDT | 3 人 |

前端入房流程：

1. 读取房间 USDT 美分价格。
2. 调用游戏合约 `quoteYionAmount(usdtPriceCents)`（兼容旧接口 `quoteTokenAmount`）。
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

### 13.0 一键生成 Java 合约包装类

Solidity 合约变更并通过测试后，在本工程执行：

```bash
npm run generate:java
```

该命令会先重新编译 Solidity，再从 Truffle artifact 提取 ABI 和 bytecode，使用与后端一致的 Web3j 5.0.0 生成 `YION`、`GameRewardPool`、`Bullfigthing`、`GoldenFlower` 和 `Landlords` Java 包装类，并更新相邻的 `moon-son-svc/src/main/java/tcbv/zhaohui/moon/contract` 目录。机器无需预装 Web3j CLI，首次执行时 Maven 会下载固定版本的生成器依赖。

如果后端不在默认的相邻目录，可指定路径：

```bash
MOON_SON_SVC_DIR=/path/to/moon-son-svc npm run generate:java
```

PowerShell：

```powershell
$env:MOON_SON_SVC_DIR = "D:\path\to\moon-son-svc"
npm run generate:java
Remove-Item Env:MOON_SON_SVC_DIR
```

生成完成后应在后端执行 `mvnw.cmd -DskipTests compile`，确认业务代码仍与最新 ABI 兼容。Java 类只是链上合约的 Web3j 调用包装，不替代 Solidity 合约本身。

如果已经有单个合约的 `.abi` 和 `.bin` 文件，可直接生成 Java 包装类，无需重新编译全部 Solidity：

```powershell
npm run generate:java:abi-bin -- --abi ".\path\Contract.abi" --bin ".\path\Contract.bin"
```

类名默认取 ABI 文件名；对于 solc 生成的 `文件名_sol_合约名.abi` 会自动提取合约名。默认包名为 `tcbv.zhaohui.moon.contract`，输出到 `build/web3j-codegen/custom-output`。也可以指定类名、包名和输出目录：

```powershell
npm run generate:java:abi-bin -- --abi ".\path\Contract.abi" --bin ".\path\Contract.bin" --name "Contract" --package "com.example.contract" --output ".\generated-java"
```

该命令使用 `scripts/web3j-codegen-pom.xml` 中固定的 Web3j 5.0.0；机器需安装 Java 和 Maven，也可通过 `JAVA_HOME`、`MAVEN_CMD` 指定位置。

### 13.1 验证三个游戏配置

Linux/macOS：

```bash
LANDLORDS_ADDRESS=0x... \
GOLDEN_FLOWER_ADDRESS=0x... \
BULLFIGTHING_ADDRESS=0x... \
npx truffle exec scripts/verify-game-contracts.js --network bscTestnet
```

验证内容包括合约代码、YION、奖励池、dealer 和 owner。

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
