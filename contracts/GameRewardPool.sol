// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title GameRewardPool
 * @notice 多游戏共享奖励池，独立管理日结排名奖池和权益回补奖池。
 *
 * 使用方式：
 * 1. 部署时传入 YION 地址。
 * 2. GoldenFlower、Bullfigthing 等游戏合约结算时，把排名池资金、回补池资金存入本合约。
 * 3. 合约 owner 按业务计算结果调用 sendRankReward / sendReplenishReward，把奖励记录到 userReward。
 * 4. 用户调用 withdrawRankReward / withdrawReplenishReward 自己提取奖励。
 */
contract GameRewardPool is ReentrancyGuard {

    error OnlyOwner(); // 只有合约 owner 可以调用。
    error InvalidAddress(); // 无效地址。
    error InvalidArrayLength(); // 无效数组长度。
    error DuplicateRecipient(); // 重复的接收用户。
    error TokenAmountMustBePositive(); // token 数量必须大于 0。
    error RewardAmountMustBePositive(); // 奖励数量必须大于 0。
    error InsufficientTokenBalance(); // token 余额不足。
    error InsufficientPoolBalance(); // 奖池余额不足。
    error InsufficientTokenAllowance(); // token 授权不足。
    error TokenTransferFromFailed(); // token transferFrom 失败。
    error TokenTransferFailed(); // token transfer 失败。

    struct UserInfo {
        // 用户可提取的日结排名奖励。
        uint256 rankReward;

        // 用户可提取的权益回补奖励。
        uint256 replenishReward;
    }

    IERC20 public immutable yion;
    address public owner;

    // 用户奖励记录。owner 每日覆盖未领取奖励，用户自己提现。
    mapping(address => UserInfo) userReward;

    // 日结排名奖池剩余未分配余额。
    uint256 public rankPoolBalance;

    // 权益回补奖池剩余未分配余额。
    uint256 public replenishPoolBalance;

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner); // 合约所有权转移。
    event RankRewardDeposited(address indexed operator, uint256 amount); // 日结排名奖池资金存入。
    event ReplenishRewardDeposited(address indexed operator, uint256 amount); // 权益回补奖池资金存入。
    event RankRewardRecorded(address indexed operator, uint256 totalAmount); // 日结排名奖励记录。
    event ReplenishRewardRecorded(address indexed operator, uint256 totalAmount); // 权益回补奖励记录。
    event RankRewardWithdrawn(address indexed user, uint256 amount); // 日结排名奖励提取。
    event ReplenishRewardWithdrawn(address indexed user, uint256 amount); // 权益回补奖励提取。

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address _yion) {
        if (_yion == address(0)) revert InvalidAddress();
        yion = IERC20(_yion);
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /**
     * @notice 游戏合约存入日结排名奖池资金。
     * @dev 调用方需要先 approve 本合约 amount。该方法只会把调用方 token 转入奖池，不会转出奖池资金。
     */
    function depositRankReward(uint256 amount) external {
        _pullToken(msg.sender, amount);
        rankPoolBalance += amount;
        emit RankRewardDeposited(msg.sender, amount);
    }

    /**
     * @notice 游戏合约存入权益回补奖池资金。
     * @dev 调用方需要先 approve 本合约 amount。该方法只会把调用方 token 转入奖池，不会转出奖池资金。
     */
    function depositReplenishReward(uint256 amount) external {
        _pullToken(msg.sender, amount);
        replenishPoolBalance += amount;
        emit ReplenishRewardDeposited(msg.sender, amount);
    }

    /**
     * @notice owner 批量记录日结排名奖励，不直接转账。
     *
     * users[i] 和 amounts[i] 一一对应。
     * 记录后用户需要自己调用 withdrawRankReward 提取。
     */
    function sendRankReward(address[] calldata users, uint256[] calldata amounts) external onlyOwner {
        uint256 totalAmount = _validateUsersAndAmounts(users, amounts);
        if (totalAmount > rankPoolBalance) revert InsufficientPoolBalance();

        rankPoolBalance -= totalAmount;
        for (uint256 i = 0; i < users.length; i++) {
            // 每日奖励覆盖前一天未领取的奖励，不跨日累加
            userReward[users[i]].rankReward = amounts[i];
        }

        emit RankRewardRecorded(msg.sender, totalAmount);
    }

    /**
     * @notice owner 批量记录权益回补奖励，不直接转账。
     *
     * users[i] 和 amounts[i] 一一对应。
     * 记录后用户需要自己调用 withdrawReplenishReward 提取。
     */
    function sendReplenishReward(address[] calldata users, uint256[] calldata amounts) external onlyOwner {
        uint256 totalAmount = _validateUsersAndAmounts(users, amounts);
        if (totalAmount > replenishPoolBalance) revert InsufficientPoolBalance();

        replenishPoolBalance -= totalAmount;
        for (uint256 i = 0; i < users.length; i++) {
            // 每日奖励覆盖前一天未领取的奖励，不跨日累加
            userReward[users[i]].replenishReward = amounts[i];
        }

        emit ReplenishRewardRecorded(msg.sender, totalAmount);
    }

    /**
     * @notice 查询用户可提取奖励。
     */
    function getRewardAmount(address user) external view returns (uint256 rankReward, uint256 replenishReward) {
        UserInfo storage info = userReward[user];
        return (info.rankReward, info.replenishReward);
    }

    /**
     * @notice 用户提取日结排名奖励。
     */
    function withdrawRankReward() external nonReentrant {
        UserInfo storage info = userReward[msg.sender];
        uint256 rewardAmount = info.rankReward;
        if (rewardAmount == 0) revert RewardAmountMustBePositive();

        info.rankReward = 0;
        _safeTransfer(msg.sender, rewardAmount);

        emit RankRewardWithdrawn(msg.sender, rewardAmount);
    }

    /**
     * @notice 用户提取权益回补奖励。
     */
    function withdrawReplenishReward() external nonReentrant {
        UserInfo storage info = userReward[msg.sender];
        uint256 rewardAmount = info.replenishReward;
        if (rewardAmount == 0) revert RewardAmountMustBePositive();

        info.replenishReward = 0;
        _safeTransfer(msg.sender, rewardAmount);

        emit ReplenishRewardWithdrawn(msg.sender, rewardAmount);
    }

    /**
     * 从指定地址拉取（转移）代币的内部函数
     * @param from 代币发送方的地址
     * @param amount 需要转移的代币数量
     * @dev 该函数会执行一系列检查以确保代币转移的安全性：
     *      1. 检查转移数量是否为正数
     *      2. 检查发送方是否有足够的代币余额
     *      3. 检查发送方是否已授权足够的代币额度
     *      4. 执行实际的代币转移操作
     * @notice 如果任何检查失败，函数会revert并抛出相应的错误
     */
    function _pullToken(address from, uint256 amount) internal {
        // 检查转移数量是否为0，如果是则抛出错误
        if (amount == 0) revert TokenAmountMustBePositive();
        // 检查发送方余额是否足够，如果不足则抛出错误
        if (yion.balanceOf(from) < amount) revert InsufficientTokenBalance();
        // 检查发送方授权额度是否足够，如果不足则抛出错误
        if (yion.allowance(from, address(this)) < amount) revert InsufficientTokenAllowance();
        // 执行代币转移，如果失败则抛出错误
        if (!yion.transferFrom(from, address(this), amount)) revert TokenTransferFromFailed();
    }

    /**
     * 安全转账函数，用于将代币从合约地址转移到指定地址
     * @param to 接收代币的目标地址
     * @param amount 要转移的代币数量
     * @dev 该函数包含多重检查以确保转账安全：
     *      1. 检查目标地址是否为零地址
     *      2. 检查转账数量是否大于零
     *      3. 检查合约是否有足够的代币余额
     *      4. 执行实际转账并确认是否成功
     * @notice 如果任何检查失败，将抛出相应的错误
     */
    function _safeTransfer(address to, uint256 amount) internal {
        // 检查目标地址是否为零地址，如果是则抛出无效地址错误
        if (to == address(0)) revert InvalidAddress();
        // 检查转账数量是否为零，如果是则抛出代币数量必须为正数的错误
        if (amount == 0) revert TokenAmountMustBePositive();
        // 检查合约余额是否足够，如果不足则抛出余额不足的错误
        if (yion.balanceOf(address(this)) < amount) revert InsufficientTokenBalance();
        // 执行代币转账，如果失败则抛出转账失败错误
        if (!yion.transfer(to, amount)) revert TokenTransferFailed();
    }

    /**
     * @dev 验证用户地址数组和金额数组的有效性
     * @param users 用户地址数组
     * @param amounts 对应的金额数组
     * @return total 所有金额的总和
     * @notice 该函数会进行以下检查：
     *         1. 确保输入数组不为空且长度相等
     *         2. 检查每个地址是否有效（非零地址）
     *         3. 检查每个金额是否为正数
     *         4. 检查是否有重复的接收地址
     */
    function _validateUsersAndAmounts(
        address[] calldata users,    // 用户地址数组
        uint256[] calldata amounts   // 对应的金额数组
    ) internal pure returns (uint256 total) {  // 返回所有金额的总和
        // 检查数组是否为空或长度是否不一致
        if (users.length == 0 || users.length != amounts.length) revert InvalidArrayLength();

        // 遍历每个用户和金额进行验证
        for (uint256 i = 0; i < users.length; i++) {
            // 检查地址是否为零地址
            if (users[i] == address(0)) revert InvalidAddress();
            // 检查金额是否为正数
            if (amounts[i] == 0) revert RewardAmountMustBePositive();
            // 检查是否有重复的接收地址
            if (_hasDuplicateRecipient(users, i)) revert DuplicateRecipient();
            // 累加金额
            total += amounts[i];
        }
    }

    /**
     * 检查收件人数组中是否存在重复地址
     * @param recipients 收件人数组
     * @param index 当前要检查的地址索引
     * @return 如果存在重复地址返回true，否则返回false
     */
    function _hasDuplicateRecipient(address[] calldata recipients, uint256 index) internal pure returns (bool) {
        // 获取当前索引处的地址
        address current = recipients[index];
        // 遍历当前索引之前的所有地址
        for (uint256 i = 0; i < index; i++) {
            // 如果发现重复地址，立即返回true
            if (recipients[i] == current) return true;
        }
        // 如果没有发现重复地址，返回false
        return false;
    }
}
