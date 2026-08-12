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

最新地址及交易哈希请始终以部署登记表为准。
