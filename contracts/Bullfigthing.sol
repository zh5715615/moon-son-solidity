// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./pricing/PancakeV2UsdtQuote.sol";

interface IBullToken {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IBullTokenMetadata is IBullToken {
    function decimals() external view returns (uint8);
}

library SafeBullERC20 {
    function safeTransfer(IBullToken token, address to, uint256 value) internal {
        require(token.transfer(to, value), "SafeERC20: transfer failed");
    }

    function safeTransferFrom(IBullToken token, address from, address to, uint256 value) internal {
        require(token.transferFrom(from, to, value), "SafeERC20: transferFrom failed");
    }

    function safeIncreaseAllowance(IBullToken token, address spender, uint256 value) internal {
        uint256 currentAllowance = token.allowance(address(this), spender);
        require(token.approve(spender, currentAllowance + value), "SafeERC20: approve failed");
    }
}

abstract contract BullReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != ENTERED, "ReentrancyGuard: reentrant call");
        _status = ENTERED;
        _;
        _status = NOT_ENTERED;
    }
}

abstract contract BullOwnable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        require(initialOwner != address(0), "Ownable: owner is zero");
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is zero");
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IBullRewardPool {
    function depositRankReward(uint256 amount) external;
    function depositReplenishReward(uint256 amount) external;
}

contract Bullfigthing is BullOwnable, BullReentrancyGuard, PancakeV2UsdtQuote {
    using SafeBullERC20 for IBullToken;

    uint256 public dpegTokenDecimals;

    IBullTokenMetadata public dpegToken;
    address public dpegTokenAddress;

    address public gameRewardPoolAddress;
    address public constant blackHoleAddress = 0x000000000000000000000000000000000000dEaD;

    uint256 public constant FEW_PERSON_ROOM = 3;
    uint256 public constant MULTI_PERSON_ROOM = 5;

    uint256 public constant ROOM_LEVEL_1 = 3000;
    uint256 public constant ROOM_LEVEL_2 = 6000;
    uint256 public constant ROOM_LEVEL_3 = 12000;
    uint256 public constant ROOM_LEVEL_4 = 200000;
    uint256 public constant ROOM_LEVEL_5 = 500000;
    uint256 public constant ROOM_LEVEL_6 = 1000000;

    uint256 public constant TOTAL_ROOMS = 15;

    struct RoomInfo {
        uint256 userCapacity;       // 房间人数上限，3人房或5人房
        uint256 roomAmount;         // 单个玩家入房 USDT 价格（美分，3000 = 30.00 USDT）
        uint256 currentUserNumber;  // 当前已加入人数
        bool enable;                // true=可加入，false=已满员等待结算
    }

    struct PlayerInfo {
        address account;
        uint256 amount;
        uint256 round;
    }

    struct RewardDistribution {
        uint256 winner;
        uint256 directPerUser;
        uint256 indirectPerUser;
        uint256 replenish;
        uint256 rank;
        uint256 blackHole;
    }

    struct TokenDistribution {
        uint256 winner;
        uint256 directPerUser;
        uint256 indirectPerUser;
        uint256 replenish;
        uint256 rank;
        uint256 blackHole;
        uint256 totalPaid;
    }

    mapping(uint256 => RoomInfo) public rooms;
    mapping(uint256 => uint256) public contractRounds;
    mapping(uint256 => address[]) private roomPlayers;
    mapping(uint256 => mapping(address => PlayerInfo)) private roomPlayerInfo;
    mapping(address => uint256) private userRoomLevels;

    event UserEnteredRoom(address indexed user, uint256 indexed level, uint256 amount);
    event UserEnteredRoomWithRound(address indexed user, uint256 indexed level, uint256 amount, uint256 round);
    event UsdtPriceQuoted(address indexed player, uint256 usdtPriceCents, uint256 tokenAmount);
    event RoomFinished(uint256 indexed level, uint256 indexed round, address indexed winner, uint256 totalAmount);
    event SettlementModeSelected(
        uint256 indexed level,
        bool usdtMode,
        uint256 escrowToken,
        uint256 quotedTokenRequired,
        uint256 paidToken
    );
    event RoomReset(uint256 indexed level, uint256 newRound);
    event RewardPoolChanged(address indexed oldRewardPool, address indexed newRewardPool);

    constructor(address beneficiary, address _gameRewardPoolAddress, address _dpegAddress) payable BullOwnable(beneficiary) {
        require(_gameRewardPoolAddress != address(0), "Reward pool is zero");
        require(_dpegAddress != address(0), "Token is zero");

        gameRewardPoolAddress = _gameRewardPoolAddress;
        dpegToken = IBullTokenMetadata(_dpegAddress);
        dpegTokenAddress = _dpegAddress;
        dpegTokenDecimals = 10 ** dpegToken.decimals();

        // 0-4: 5 人 3K 房；5-9: 5 人 6K 房；10-14: 5 人 12K 房。
        for (uint256 level = 0; level < 5; level++) {
            _initRoom(level, MULTI_PERSON_ROOM, ROOM_LEVEL_1);
        }
        for (uint256 level = 5; level < 10; level++) {
            _initRoom(level, MULTI_PERSON_ROOM, ROOM_LEVEL_2);
        }
        for (uint256 level = 10; level < TOTAL_ROOMS; level++) {
            _initRoom(level, MULTI_PERSON_ROOM, ROOM_LEVEL_3);
        }
    }

    function _initRoom(uint256 level, uint256 userCapacity, uint256 roomAmount) internal {
        rooms[level] = RoomInfo(userCapacity, roomAmount, 0, true);
        contractRounds[level] = 1;
    }

    function setGameRewardPoolAddress(address newRewardPoolAddress) external onlyOwner {
        require(newRewardPoolAddress != address(0), "Reward pool is zero");
        address oldRewardPool = gameRewardPoolAddress;
        gameRewardPoolAddress = newRewardPoolAddress;
        emit RewardPoolChanged(oldRewardPool, newRewardPoolAddress);
    }

    function enterTheRoom(uint256 level) external nonReentrant {
        require(level < TOTAL_ROOMS, "Invalid room level");

        RoomInfo storage room = rooms[level];
        require(room.enable, "Room is not available");
        require(userRoomLevels[msg.sender] == 0 || !_isUserInRoom(msg.sender), "User already in room");
        require(roomPlayerInfo[level][msg.sender].account == address(0), "User already in this room");

        uint256 tokenAmount = _quoteTokenAmount(room.roomAmount);
        require(IBullToken(dpegTokenAddress).allowance(msg.sender, address(this)) >= tokenAmount, "Token allowance is not enough");

        IBullToken token = IBullToken(dpegTokenAddress);
        token.safeTransferFrom(msg.sender, address(this), tokenAmount);

        roomPlayers[level].push(msg.sender);
        roomPlayerInfo[level][msg.sender] = PlayerInfo(msg.sender, tokenAmount, contractRounds[level]);
        userRoomLevels[msg.sender] = level + 1;

        room.currentUserNumber++;
        if (room.currentUserNumber >= room.userCapacity) {
            room.enable = false;
        }

        emit UsdtPriceQuoted(msg.sender, room.roomAmount, tokenAmount);
        emit UserEnteredRoom(msg.sender, level, tokenAmount);
        emit UserEnteredRoomWithRound(msg.sender, level, tokenAmount, contractRounds[level]);
    }

    receive() external payable {}

    function sendInstantReward(
        uint256 level,
        address winner,
        address[] memory directUser,
        address[] memory indirectUser
    ) public onlyOwner nonReentrant {
        require(level < TOTAL_ROOMS, "Invalid room level");
        require(!rooms[level].enable, "Room not finished");
        require(winner != address(0), "Winner address is zero");
        require(_isRoomPlayer(level, winner), "Winner not in room");

        uint256 userCapacity = rooms[level].userCapacity;
        require(directUser.length <= userCapacity, "Direct user list too long");
        require(indirectUser.length <= userCapacity, "Indirect user list too long");

        uint256 escrowToken = _roomEscrow(level);
        uint256 totalUsdtCents = rooms[level].roomAmount * userCapacity;
        (uint256 paidToken, uint256 quotedTokenRequired, bool usdtMode) = _distributeRewards(
            totalUsdtCents,
            escrowToken,
            userCapacity,
            winner,
            directUser,
            indirectUser
        );

        uint256 finishedRound = contractRounds[level];
        _resetRoom(level);
        emit SettlementModeSelected(level, usdtMode, escrowToken, quotedTokenRequired, paidToken);
        emit RoomFinished(level, finishedRound, winner, totalUsdtCents);
    }

    function _distributeRewards(
        uint256 totalAmount,
        uint256 escrowToken,
        uint256 userCapacity,
        address winner,
        address[] memory directUser,
        address[] memory indirectUser
    ) internal returns (uint256 paidToken, uint256 quotedTokenRequired, bool usdtMode) {
        RewardDistribution memory usdt = _calculateDistribution(
            totalAmount,
            userCapacity,
            directUser.length,
            indirectUser.length
        );
        TokenDistribution memory reward = _quoteDistribution(usdt, directUser.length, indirectUser.length);
        quotedTokenRequired = reward.totalPaid;
        usdtMode = quotedTokenRequired <= escrowToken;
        if (!usdtMode) {
            reward = _calculateTokenFallback(
                escrowToken,
                userCapacity,
                directUser.length,
                indirectUser.length
            );
        }
        IBullToken token = IBullToken(dpegTokenAddress);
        require(token.balanceOf(address(this)) >= reward.totalPaid, "Contract token balance is not enough");

        token.safeTransfer(winner, reward.winner);
        _distributePoolRewards(token, reward.blackHole, reward.replenish, reward.rank);
        _transferReferralRewards(token, directUser, reward.directPerUser, "Direct user address is zero");
        _transferReferralRewards(token, indirectUser, reward.indirectPerUser, "Indirect user address is zero");
        return (reward.totalPaid, quotedTokenRequired, usdtMode);
    }

    function _calculateDistribution(
        uint256 totalAmount,
        uint256 userCapacity,
        uint256 directCount,
        uint256 indirectCount
    ) internal pure returns (RewardDistribution memory reward) {
        reward.winner = totalAmount * 70 / 100;
        reward.replenish = totalAmount * 10 / 100;
        reward.rank = totalAmount * 5 / 100;
        reward.directPerUser = (totalAmount * 3 / 100) / userCapacity;
        reward.indirectPerUser = (totalAmount * 2 / 100) / userCapacity;
        uint256 paidReferralAmount = reward.directPerUser * directCount
            + reward.indirectPerUser * indirectCount;
        reward.blackHole = totalAmount
            - reward.winner
            - reward.replenish
            - reward.rank
            - paidReferralAmount;
    }

    function _quoteDistribution(
        RewardDistribution memory usdt,
        uint256 directCount,
        uint256 indirectCount
    ) internal view returns (TokenDistribution memory tokenAmount) {
        tokenAmount.winner = _quoteTokenAmount(usdt.winner);
        tokenAmount.replenish = _quoteTokenAmount(usdt.replenish);
        tokenAmount.rank = _quoteTokenAmount(usdt.rank);
        tokenAmount.blackHole = _quoteTokenAmount(usdt.blackHole);
        if (directCount > 0) tokenAmount.directPerUser = _quoteTokenAmount(usdt.directPerUser);
        if (indirectCount > 0) tokenAmount.indirectPerUser = _quoteTokenAmount(usdt.indirectPerUser);
        tokenAmount.totalPaid = tokenAmount.winner
            + tokenAmount.replenish
            + tokenAmount.rank
            + tokenAmount.blackHole
            + tokenAmount.directPerUser * directCount
            + tokenAmount.indirectPerUser * indirectCount;
    }

    function _calculateTokenFallback(
        uint256 escrowToken,
        uint256 userCapacity,
        uint256 directCount,
        uint256 indirectCount
    ) internal pure returns (TokenDistribution memory tokenAmount) {
        tokenAmount.winner = escrowToken * 70 / 100;
        tokenAmount.replenish = escrowToken * 10 / 100;
        tokenAmount.rank = escrowToken * 5 / 100;
        tokenAmount.directPerUser = (escrowToken * 3 / 100) / userCapacity;
        tokenAmount.indirectPerUser = (escrowToken * 2 / 100) / userCapacity;
        uint256 paidReferralAmount = tokenAmount.directPerUser * directCount
            + tokenAmount.indirectPerUser * indirectCount;
        tokenAmount.blackHole = escrowToken
            - tokenAmount.winner
            - tokenAmount.replenish
            - tokenAmount.rank
            - paidReferralAmount;
        tokenAmount.totalPaid = escrowToken;
    }

    function _distributePoolRewards(
        IBullToken token,
        uint256 blackHoleAmount,
        uint256 replenishAmount,
        uint256 rankAmount
    ) internal {
        token.safeTransfer(blackHoleAddress, blackHoleAmount);
        _depositReplenishReward(replenishAmount);
        _depositRankReward(rankAmount);
    }

    function _transferReferralRewards(
        IBullToken token,
        address[] memory users,
        uint256 amount,
        string memory zeroAddressMessage
    ) internal {
        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), zeroAddressMessage);
            token.safeTransfer(users[i], amount);
        }
    }

    function getRoomInfo(uint256 level) external view returns (uint256[] memory values, address[] memory addrs) {
        require(level < TOTAL_ROOMS, "Invalid room level");
        RoomInfo storage room = rooms[level];

        values = new uint256[](5);
        values[0] = room.userCapacity;
        values[1] = room.roomAmount;
        values[2] = room.currentUserNumber;
        values[3] = room.enable ? 1 : 0;
        values[4] = contractRounds[level];

        addrs = new address[](roomPlayers[level].length);
        for (uint256 i = 0; i < roomPlayers[level].length; i++) {
            addrs[i] = roomPlayers[level][i];
        }
    }

    function getPlayerInfo(uint256 level, address player) external view returns (uint256[] memory values, bool[] memory flags) {
        require(level < TOTAL_ROOMS, "Invalid room level");
        PlayerInfo storage info = roomPlayerInfo[level][player];

        values = new uint256[](2);
        values[0] = info.amount;
        values[1] = info.round;

        flags = new bool[](1);
        flags[0] = info.account != address(0);
    }

    function getUserRoom(address user) external view returns (uint256 level, bool joined) {
        uint256 storedLevel = userRoomLevels[user];
        if (storedLevel == 0) {
            return (0, false);
        }
        return (storedLevel - 1, _isUserInRoom(user));
    }

    function _resetRoom(uint256 level) internal {
        address[] storage players = roomPlayers[level];
        for (uint256 i = 0; i < players.length; i++) {
            delete roomPlayerInfo[level][players[i]];
            delete userRoomLevels[players[i]];
        }
        delete roomPlayers[level];

        rooms[level].enable = true;
        rooms[level].currentUserNumber = 0;
        contractRounds[level] += 1;

        emit RoomReset(level, contractRounds[level]);
    }

    function _roomEscrow(uint256 level) internal view returns (uint256 totalAmount) {
        address[] storage players = roomPlayers[level];
        for (uint256 i = 0; i < players.length; i++) {
            totalAmount += roomPlayerInfo[level][players[i]].amount;
        }
    }

    function _isRoomPlayer(uint256 level, address player) internal view returns (bool) {
        return roomPlayerInfo[level][player].account != address(0);
    }

    function _isUserInRoom(address user) internal view returns (bool) {
        uint256 storedLevel = userRoomLevels[user];
        if (storedLevel == 0) {
            return false;
        }
        uint256 level = storedLevel - 1;
        return roomPlayerInfo[level][user].account != address(0);
    }

    function _depositRankReward(uint256 amount) internal {
        IBullToken token = IBullToken(dpegTokenAddress);
        token.safeIncreaseAllowance(gameRewardPoolAddress, amount);
        IBullRewardPool(gameRewardPoolAddress).depositRankReward(amount);
    }

    function _depositReplenishReward(uint256 amount) internal {
        IBullToken token = IBullToken(dpegTokenAddress);
        token.safeIncreaseAllowance(gameRewardPoolAddress, amount);
        IBullRewardPool(gameRewardPoolAddress).depositReplenishReward(amount);
    }

    function _paymentToken() internal view override returns (address) {
        return dpegTokenAddress;
    }
}
