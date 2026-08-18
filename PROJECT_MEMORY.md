# 工程记忆

## 项目

- 工程：弈元游戏 Solidity 合约
- 框架：Truffle
- 编译器：Solidity 0.8.21
- 当前远程测试网：BNB Smart Chain Testnet，Chain ID 97
- 区块浏览器：https://testnet.bscscan.com

## 部署记忆规则

- 机器可读的权威记录：`deployments/bsc-testnet-97.json`
- 人工查看的整理清单：`DEPLOYMENTS.md`
- 部署脚本必须调用 `scripts/lib/record-deployment.js` 自动登记。
- 部署时间取交易所在区块的时间戳，同时保存 UTC 和北京时间。
- 同一合约重新部署时追加新记录，不覆盖旧记录，以保留完整历史。
- 私钥、助记词和带访问令牌的 RPC URL 不得写入部署记录或提交 Git。

## 当前测试网公共配置

- 部署/管理账户：`0x7c92cd77d3fbA3ea33f7D94254bf3E23B25513C2`
- ERC-20 Token：`0x7ef3D2a397cd368A33d35c52Db42013f691aa7C7`
- Token decimals：2
- GameRewardPool：`0x720b0dA83e69Fa7f4f2297a9e45B166AeeC3E937`

## YION 测试网发行与流动性

- 最新链上 YION（8 位、白名单、PancakeSwap 原生 Fee-on-Transfer 版）：`0x85C6911759989f1355E63AeA55e71C0336Cbdab3`
- 名称/符号：`YION` / `YION`
- decimals：8
- 固定总量：100,000,000 YION；构造时一次性铸造，无增发入口。
- PancakeSwap V2 YION/USDT Pair：`0x724a4EE29c83d57FF334f17a2D89c7f73AbadE7B`
- 测试网 USDT：`0x5B32Cc7d18643073BDB15dAfafC5C35E736c91a5`
- 初始储备：100,000,000 YION + 10,000 USDT。
- 初始比例：`1 USDT = 10,000 YION`。
- 全部 YION 已进入流动性池，LP Token 由部署账户持有。
- Pair 激活后前 30 分钟仅允许代码内写死的 100 个白名单地址交易；单笔按
  PancakeSwap 实时报价最大允许 200 USDT，并禁止普通转账/其他 Pair 绕过。
- 200 USDT 上限在构造时读取报价 Token 的 `decimals()` 后换算为原始单位，不假定
  USDT 固定为 6 位或 18 位；边界使用 `>`，因此正好 200 USDT 可以交易。
- 30 分钟结束后限制自动永久失效，所有地址和金额开放。
- 最新链上版本可以直接通过 PancakeSwap V2 的 Fee-on-Transfer 兼容入口交易：官方 Pair
  买入和卖出均扣3% YION，手续费 YION 直接发送到
  `0xa24bDb249e80574A96D8B02b148E81B9be684675`，不累计、不换 USDT。源码另有独立
  `feeExempt` 白名单，部署账户和 Token 合约自身默认免手续费，由部署账户管理。
- 本次于 2026-08-18 20:31:04 +08:00 激活，首轮白名单限制截至
  2026-08-18 21:01:04 +08:00（Unix `1787058064`）。
- 上一版额外扣费 YION 为 `0x6864...Dc4df`，Pair 为 `0x9F69...46A1d`。
- 上一版 18 位 YION `0x9e6C...cE3a` 及 Pair `0x92F4...073F` 仍保留在链上，
  但不再是最新版本。
- 当前三个游戏合约仍使用原业务 Token `0x7ef3...a7C7`，未切换到 YION。

## 游戏合约计价规则

- 三个游戏合约构造函数保持不变。
- 房间配置数值改为 USDT 美分整数：`3000 = 30.00 USDT`。
- 玩家仍使用业务 Token 支付；入房时通过 PancakeSwap V2 `getAmountsIn`
  按当前 Token/USDT 直连池报价计算 Token 托管数量。
- Chain ID 56 自动使用 BSC 主网 USDT/Router；Chain ID 97 自动使用测试网
  USDT/Router；其他链拒绝报价。
- 每个玩家的 Token 托管数量按其入房时的报价独立记录。
- 所有实际押注和奖励金额使用 USDT 美分记账。结算时先对赢家、黑洞、
  回补池、排名池、直推、间推和退款分别调用 V2 报价，计算所需 Token。
- 若 U 报价所需 Token 不超过本局实际托管 Token，使用 U 实时报价结算；
  若超过，则自动按本局实际 Token 执行相同百分比分配，不回滚、不挪用
  其他房间资金。
- `SettlementModeSelected` 事件记录本局选择的模式、托管 Token、U 报价
  所需 Token 和最终支付 Token。`usdtMode=true` 表示 U 模式。
- U 模式产生的剩余 Token 留在游戏合约中；模式判断仍只以本局 escrow
  为上限，历史余额不会使本局承担超过自身托管额的结算。
- 取消房间不重新报价，始终原样退回玩家入房时实际托管的 Token。
- 前端应先调用 `quoteTokenAmount(usdtPriceCents)`，并仅授权本次需要的
  Token 数量（或很小容差），不要无限授权。V2 现货报价可能受到池价格操纵。
- 当前源码已包含结算时重新报价逻辑，链上现有三个游戏地址均不是最终源码版本，
  需要重新部署；GameRewardPool 无需重新部署。

最新地址及交易哈希请始终以部署登记表为准。
