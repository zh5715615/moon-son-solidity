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
