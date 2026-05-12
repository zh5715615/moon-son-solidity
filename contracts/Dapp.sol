// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract Dapp is Ownable, ReentrancyGuard {

    uint256 public usdtTokenDecimals; 

    uint256 public dpegTokenDecimals; 

    IERC20Metadata public usdtToken;
    address public usdtTokenAddress;

    IERC20Metadata public dpegToken;
    address public dpegTokenAddress;

    address rankPoolAddress;           //排行榜资金地址
    address replenishPoolAddress;      //回补池资金地址
    address constant blackHoleAddress = 0x000000000000000000000000000000000000dEaD;          //黑洞地址

    struct UserInfo {
        uint256 rankReward;         // 排行奖励
        uint256 replenishReward;    // 回补奖励
    }

    uint constant FEW_PERSON_ROOM = 3;   //少人房人数
    uint constant MULTI_PERSON_ROOM = 5; //多人房人数

    uint constant ROOM_LEVEL_1 = 25000;
    uint constant ROOM_LEVEL_2 = 50000;
    uint constant ROOM_LEVEL_3 = 100000;
    uint constant ROOM_LEVEL_4 = 200000;
    uint constant ROOM_LEVEL_5 = 500000;
    uint constant ROOM_LEVEL_6 = 1000000;

    struct RoomInfo {
        uint userCapacity;          //用户数量
        uint256 roomAmount;         //房间金额
        uint currentUserNumber;     //当前房间人数
        bool enable;                //房间是否可加入
    }

    mapping(uint => RoomInfo) public rooms;

    mapping(address => UserInfo) userReward;

    event UserEnteredRoom(address indexed user, uint indexed level, uint256 amount);
    event RankRewardWithdrawn(address indexed user, uint256 amount);
    event ReplenishRewardWithdrawn(address indexed user, uint256 amount);

    constructor(address beneficiary, address _rankPoolAddress, address _replenishPoolAddress, 
                address _usdtAddress, address _dpegAddress) payable Ownable(beneficiary) {
        rankPoolAddress = _rankPoolAddress;
        replenishPoolAddress = _replenishPoolAddress;
        
        usdtToken = IERC20Metadata(_usdtAddress);
        usdtTokenAddress = _usdtAddress;
        usdtTokenDecimals = 10 ** usdtToken.decimals();
        
        dpegToken = IERC20Metadata(_dpegAddress);
        dpegTokenAddress = _dpegAddress;
        dpegTokenDecimals = 10 ** dpegToken.decimals();

        rooms[0] = RoomInfo(FEW_PERSON_ROOM, ROOM_LEVEL_1 * dpegTokenDecimals, 0, true);
        rooms[1] = RoomInfo(FEW_PERSON_ROOM, ROOM_LEVEL_2 * dpegTokenDecimals, 0, true);
        rooms[2] = RoomInfo(FEW_PERSON_ROOM, ROOM_LEVEL_3 * dpegTokenDecimals, 0, true);
        rooms[3] = RoomInfo(FEW_PERSON_ROOM, ROOM_LEVEL_4 * dpegTokenDecimals, 0, true);
        rooms[4] = RoomInfo(FEW_PERSON_ROOM, ROOM_LEVEL_5 * dpegTokenDecimals, 0, true);
        rooms[5] = RoomInfo(FEW_PERSON_ROOM, ROOM_LEVEL_6 * dpegTokenDecimals, 0, true);
        rooms[6] = RoomInfo(MULTI_PERSON_ROOM, ROOM_LEVEL_1 * dpegTokenDecimals, 0, true);
        rooms[7] = RoomInfo(MULTI_PERSON_ROOM, ROOM_LEVEL_2 * dpegTokenDecimals, 0, true);
        rooms[8] = RoomInfo(MULTI_PERSON_ROOM, ROOM_LEVEL_3 * dpegTokenDecimals, 0, true);
        rooms[9] = RoomInfo(MULTI_PERSON_ROOM, ROOM_LEVEL_4 * dpegTokenDecimals, 0, true);
        rooms[10] = RoomInfo(MULTI_PERSON_ROOM, ROOM_LEVEL_5 * dpegTokenDecimals, 0, true);
        rooms[11] = RoomInfo(MULTI_PERSON_ROOM, ROOM_LEVEL_6 * dpegTokenDecimals, 0, true);
    }

    function enterTheRoom(uint level) public nonReentrant {
        require(level >= 0 && level < 12, "Invalid room level");
        require(rooms[level].enable, "Room is not available");
        uint roomAmount = rooms[level].roomAmount;
        uint currentUserNumber = rooms[level].currentUserNumber;
        uint userCapacity = rooms[level].userCapacity;

        uint256 rankRewardAmount = roomAmount * 5 / 100;
        uint256 replenishRewardAmount = roomAmount * 10 / 100;
        uint256 destroyAmount = roomAmount * 10 /100;
        uint256 remainingAmount = roomAmount - rankRewardAmount - replenishRewardAmount - destroyAmount;

        uint256 currentAllowance = IERC20(dpegToken).allowance(msg.sender, address(this));
        require(currentAllowance >= roomAmount, "Token allowance is not enough");

        SafeERC20.safeTransferFrom(dpegToken, msg.sender, rankPoolAddress, rankRewardAmount);
        // TODO 这里要去pancake上把replenishRewardAmount个dpegToken换成usdtToken，然后转到replenishPoolAddress；
        SafeERC20.safeTransferFrom(dpegToken, msg.sender, replenishPoolAddress, replenishRewardAmount);
        SafeERC20.safeTransferFrom(dpegToken, msg.sender, blackHoleAddress, destroyAmount);
        SafeERC20.safeTransferFrom(dpegToken, msg.sender, address(this), remainingAmount);
        if (currentUserNumber + 1 < userCapacity) {
            rooms[level].currentUserNumber += 1;
        } else {
            rooms[level].enable = false;
        }
        emit UserEnteredRoom(msg.sender, level, roomAmount);
    }

    function sendInstantReward(uint level, address winner, address[] memory directUser, address[] memory indirectUser) public onlyOwner {
        require(level >= 0 && level < 12, "Invalid room level");
        require(winner != address(0), "Winner address is zero");

        uint userCapacity = rooms[level].userCapacity;
        require(directUser.length <= userCapacity, "Direct user list too long");
        require(indirectUser.length <= userCapacity, "Indirect user list too long");
        
        uint256 roomAmount = rooms[level].roomAmount;
        uint256 totalAmount = roomAmount * userCapacity;

        uint256 winnerReward = totalAmount * 70 / 100;
        uint256 directReward = roomAmount * 3 / 100;
        uint256 indirectReward = roomAmount * 2 / 100;

        uint256 requiredBalance = winnerReward + directReward * directUser.length + indirectReward * indirectUser.length;
        uint256 contractBalance = IERC20(dpegToken).balanceOf(address(this));
        require(contractBalance >= requiredBalance, "Contract token balance is not enough");

        SafeERC20.safeTransfer(dpegToken, winner, winnerReward);
        for (uint i = 0; i < directUser.length; i++) {
            require(directUser[i] != address(0), "Direct user address is zero");
            SafeERC20.safeTransfer(dpegToken, directUser[i], directReward);
        }
        for (uint i = 0; i < indirectUser.length; i++) {
            require(indirectUser[i] != address(0), "Indirect user address is zero");
            SafeERC20.safeTransfer(dpegToken, indirectUser[i], indirectReward);
        }

        rooms[level].enable = true;
        rooms[level].currentUserNumber = 0;
    }

    function sendRankReward(address[] memory rankUsers, uint256[] memory rewardAmounts) public onlyOwner {
        require(rankUsers.length <= 10, "Rank user list too long");
        require(rewardAmounts.length <= 10, "Reward amount list too long");
        require(rankUsers.length == rewardAmounts.length, "Rank user list is not eq Reward amount list");

        for (uint i = 0; i < rankUsers.length; i++) {
            require(rankUsers[i] != address(0), "Rank user address is zero");
            userReward[rankUsers[i]].rankReward += rewardAmounts[i];
        }
    }

    function getRewardAmount(address user) public view returns (uint256, uint256) {
        return (userReward[user].rankReward, userReward[user].replenishReward);
    }

    function withdrawRankReward() public nonReentrant {
        UserInfo storage userInfo = userReward[msg.sender];
        require(userInfo.rankReward > 0, "Rank reward is zero");
        userReward[msg.sender].rankReward = 0;
        uint256 poolBalance = IERC20(dpegToken).balanceOf(rankPoolAddress);
        require(poolBalance >= userInfo.rankReward, "User rank reward amount large of pool balance");
        uint256 poolAllowance = IERC20(dpegToken).allowance(rankPoolAddress, address(this));
        require(poolAllowance >= userInfo.rankReward, "Rank pool allowance is not enough");
        SafeERC20.safeTransferFrom(dpegToken, rankPoolAddress, msg.sender, userInfo.rankReward);
        emit RankRewardWithdrawn(msg.sender, userInfo.rankReward);
    }

    function sendreplenishReward(address[] memory replenishUsers, uint256[] memory rewardAmounts) public onlyOwner {
        require(replenishUsers.length <= 20, "Replenish user list too long");
        require(rewardAmounts.length <= 20, "Replenish amount list too long");
        require(replenishUsers.length == rewardAmounts.length, "Replenish user list is not eq Replenish amount list");

        for (uint i = 0; i < replenishUsers.length; i++) {
            require(replenishUsers[i] != address(0), "Replenish user address is zero"); 
            userReward[replenishUsers[i]].replenishReward += rewardAmounts[i];
        }
    }

    function withdrawReplenishReward() public {
        UserInfo storage userInfo = userReward[msg.sender];
        require(userInfo.replenishReward > 0, "Replenish reward is zero");
        userReward[msg.sender].replenishReward = 0;
        uint256 poolBalance = IERC20(usdtToken).balanceOf(replenishPoolAddress);
        require(poolBalance >= userInfo.replenishReward, "User replenish reward amount large of pool balance");
        uint256 poolAllowance = IERC20(usdtToken).allowance(replenishPoolAddress, address(this));
        require(poolAllowance >= userInfo.replenishReward, "Replenish pool allowance is not enough");
        SafeERC20.safeTransferFrom(usdtToken, replenishPoolAddress, msg.sender, userInfo.replenishReward);
        emit ReplenishRewardWithdrawn(msg.sender, userInfo.replenishReward);
    }
}