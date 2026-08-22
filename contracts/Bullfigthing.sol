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
    function safeTransfer(IBullToken yion, address to, uint256 value) internal {
        require(yion.transfer(to, value), "SafeERC20: transfer failed");
    }

    function safeTransferFrom(IBullToken yion, address from, address to, uint256 value) internal {
        require(yion.transferFrom(from, to, value), "SafeERC20: transferFrom failed");
    }

    function safeIncreaseAllowance(IBullToken yion, address spender, uint256 value) internal {
        uint256 currentAllowance = yion.allowance(address(this), spender);
        require(yion.approve(spender, currentAllowance + value), "SafeERC20: approve failed");
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

    uint256 public yionUnit;

    IBullTokenMetadata public yionMetadata;
    address public yionAddress;

    address public gameRewardPoolAddress;
    address public constant blackHoleAddress = 0x000000000000000000000000000000000000dEaD;

    uint256 public constant MULTI_PERSON_ROOM = 5;

    uint256 public constant TOTAL_ROOMS = 15;
    uint256 public constant ENTRY_FEE_USDT_CENTS = 500;

    struct RoomInfo {
        uint256 userCapacity;       // 房间人数上限，3人房或5人房
        uint256 roomAmount;         // 单个玩家入房 USDT 价格（美分，500 = 5.00 USDT）
        uint256 currentUserNumber;  // 当前已加入人数
        bool enable;                // true=可加入，false=已满员等待结算
    }

    struct PlayerInfo {
        address account;
        uint256 amount;
        uint256 round;
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
    event RoomRefunded(uint256 indexed level, uint256 indexed round, uint256 totalRefunded);
    event SettlementModeSelected(
        uint256 indexed level,
        bool usdtMode,
        uint256 escrowToken,
        uint256 quotedTokenRequired,
        uint256 paidToken
    );
    event RoomReset(uint256 indexed level, uint256 newRound);
    event RewardPoolChanged(address indexed oldRewardPool, address indexed newRewardPool);

    constructor(address beneficiary, address _gameRewardPoolAddress, address _yionAddress) payable BullOwnable(beneficiary) {
        require(_gameRewardPoolAddress != address(0), "Reward pool is zero");
        require(_yionAddress != address(0), "YION is zero");

        gameRewardPoolAddress = _gameRewardPoolAddress;
        yionMetadata = IBullTokenMetadata(_yionAddress);
        yionAddress = _yionAddress;
        yionUnit = 10 ** yionMetadata.decimals();

        // 0-14：15 个 5 人房，每位玩家入场费统一为 5 USDT。
        for (uint256 level = 0; level < TOTAL_ROOMS; level++) {
            _initRoom(level, MULTI_PERSON_ROOM, ENTRY_FEE_USDT_CENTS);
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

        uint256 yionAmount = _quoteTokenAmount(room.roomAmount);
        require(IBullToken(yionAddress).allowance(msg.sender, address(this)) >= yionAmount, "YION allowance is not enough");

        IBullToken yion = IBullToken(yionAddress);
        yion.safeTransferFrom(msg.sender, address(this), yionAmount);

        roomPlayers[level].push(msg.sender);
        roomPlayerInfo[level][msg.sender] = PlayerInfo(msg.sender, yionAmount, contractRounds[level]);
        userRoomLevels[msg.sender] = level + 1;

        room.currentUserNumber++;
        if (room.currentUserNumber >= room.userCapacity) {
            room.enable = false;
        }

        emit UsdtPriceQuoted(msg.sender, room.roomAmount, yionAmount);
        emit UserEnteredRoom(msg.sender, level, yionAmount);
        emit UserEnteredRoomWithRound(msg.sender, level, yionAmount, contractRounds[level]);
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

    /**
     * @notice 异常释放房间，原路退回当前所有玩家入房时托管的 YION。
     */
    function refundRoom(uint256 level) external onlyOwner nonReentrant {
        require(level < TOTAL_ROOMS, "Invalid room level");
        address[] storage players = roomPlayers[level];
        require(players.length > 0, "Room has no players");

        IBullToken yion = IBullToken(yionAddress);
        uint256 totalRefunded;
        uint256 refundedRound = contractRounds[level];
        for (uint256 i = 0; i < players.length; i++) {
            uint256 amount = roomPlayerInfo[level][players[i]].amount;
            if (amount > 0) {
                totalRefunded += amount;
                yion.safeTransfer(players[i], amount);
            }
        }

        _resetRoom(level);
        emit RoomRefunded(level, refundedRound, totalRefunded);
    }

    function _distributeRewards(
        uint256 totalUsdtCents,
        uint256 escrowToken,
        uint256 userCapacity,
        address winner,
        address[] memory directUser,
        address[] memory indirectUser
    ) internal returns (uint256 paidToken, uint256 quotedTokenRequired, bool usdtMode) {
        // 当前报价所需 YION 不超过房间托管额时，按当前 USDT 等值结算；
        // 超过托管额时，最多按本局实际托管余额结算。
        quotedTokenRequired = _quoteTokenAmount(totalUsdtCents);
        usdtMode = quotedTokenRequired <= escrowToken;
        uint256 settlementToken = usdtMode ? quotedTokenRequired : escrowToken;
        TokenDistribution memory reward = _calculateTokenDistribution(
            settlementToken,
            userCapacity,
            directUser.length,
            indirectUser.length
        );
        IBullToken yion = IBullToken(yionAddress);
        require(yion.balanceOf(address(this)) >= reward.totalPaid, "Contract YION balance is not enough");

        yion.safeTransfer(winner, reward.winner);
        _distributePoolRewards(yion, reward.blackHole, reward.replenish, reward.rank);
        _transferReferralRewards(yion, directUser, reward.directPerUser, "Direct user address is zero");
        _transferReferralRewards(yion, indirectUser, reward.indirectPerUser, "Indirect user address is zero");
        return (reward.totalPaid, quotedTokenRequired, usdtMode);
    }

    function _calculateTokenDistribution(
        uint256 settlementToken,
        uint256 userCapacity,
        uint256 directCount,
        uint256 indirectCount
    ) internal pure returns (TokenDistribution memory tokenAmount) {
        tokenAmount.winner = settlementToken * 70 / 100;
        tokenAmount.replenish = settlementToken * 10 / 100;
        tokenAmount.rank = settlementToken * 5 / 100;
        tokenAmount.directPerUser = (settlementToken * 3 / 100) / userCapacity;
        tokenAmount.indirectPerUser = (settlementToken * 2 / 100) / userCapacity;
        uint256 paidReferralAmount = tokenAmount.directPerUser * directCount
            + tokenAmount.indirectPerUser * indirectCount;
        tokenAmount.blackHole = settlementToken
            - tokenAmount.winner
            - tokenAmount.replenish
            - tokenAmount.rank
            - paidReferralAmount;
        tokenAmount.totalPaid = settlementToken;
    }

    function _distributePoolRewards(
        IBullToken yion,
        uint256 blackHoleAmount,
        uint256 replenishAmount,
        uint256 rankAmount
    ) internal {
        yion.safeTransfer(blackHoleAddress, blackHoleAmount);
        _depositReplenishReward(replenishAmount);
        _depositRankReward(rankAmount);
    }

    function _transferReferralRewards(
        IBullToken yion,
        address[] memory users,
        uint256 amount,
        string memory zeroAddressMessage
    ) internal {
        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), zeroAddressMessage);
            yion.safeTransfer(users[i], amount);
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
        IBullToken yion = IBullToken(yionAddress);
        yion.safeIncreaseAllowance(gameRewardPoolAddress, amount);
        IBullRewardPool(gameRewardPoolAddress).depositRankReward(amount);
    }

    function _depositReplenishReward(uint256 amount) internal {
        IBullToken yion = IBullToken(yionAddress);
        yion.safeIncreaseAllowance(gameRewardPoolAddress, amount);
        IBullRewardPool(gameRewardPoolAddress).depositReplenishReward(amount);
    }

    function _paymentToken() internal view override returns (address) {
        return yionAddress;
    }
}
