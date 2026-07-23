// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILandlordsRewardPool {
    function depositRankReward(uint256 amount) external;
    function depositReplenishReward(uint256 amount) external;
}

interface ILandlordsToken {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

/**
 * @title Landlords
 * @notice 斗地主链上资金托管与结算合约。叫抢地主、发牌和出牌均在后端链下完成。
 *
 * 房间配置：
 * roomId  1-9  : 3人场，底注1K，单人托管上限20K。
 * roomId 10-18 : 3人场，底注3K，单人托管上限60K。
 * roomId 19-27 : 3人场，底注5K，单人托管上限100K。
 */
contract Landlords {
    error OnlyDealer();
    error InvalidRoomId();
    error RoomNotOpen();
    error RoomNotLocked();
    error RoomFull();
    error AlreadyInRoom();
    error InvalidArrayLength();
    error InvalidRecipient();
    error InvalidWinner();
    error InvalidWinnerCount();
    error InvalidBetAmount();
    error InvalidBetTotal();
    error InvalidRewardAmount();
    error InvalidPayoutTotal();
    error TokenAmountMustBePositive();
    error InsufficientTokenBalance();
    error InsufficientTokenAllowance();
    error TokenTransferFromFailed();
    error TokenTransferFailed();
    error InsufficientContractTokenBalance();

    uint256 public constant TOTAL_ROOMS = 27;
    uint256 public constant ROOM_PLAYERS = 3;

    ILandlordsToken public immutable token;
    address public immutable dealer;
    address public immutable rewardPool;
    uint256 public immutable tokenUnit;

    enum RoomStatus { Waiting, Locked }

    struct RoomConfig {
        uint256 betUnit;
        uint256 maxDeposit;
    }

    struct Player {
        address addr;
        uint256 deposit;
    }

    struct Room {
        RoomStatus status;
        uint256 roundNumber;
        uint256 escrow;
        uint256 playerCount;
        address[3] playerAddrs;
    }

    mapping(uint256 => Room) private rooms;
    mapping(uint256 => mapping(address => Player)) private players;
    mapping(address => uint256) private userRoomIds;

    event PlayerJoined(uint256 indexed roomId, address indexed player, uint256 deposit, uint256 round);
    event RoomLocked(uint256 indexed roomId, uint256 round, uint256 escrow);
    event RoomSettled(uint256 indexed roomId, uint256 round, uint256 totalBet, uint256 totalPaid);
    event RoomRefunded(uint256 indexed roomId, uint256 round, uint256 totalRefunded);
    event RoomReset(uint256 indexed roomId, uint256 newRound);

    modifier onlyDealer() {
        if (msg.sender != dealer) revert OnlyDealer();
        _;
    }

    modifier validRoom(uint256 roomId) {
        if (roomId < 1 || roomId > TOTAL_ROOMS) revert InvalidRoomId();
        _;
    }

    constructor(address tokenAddress, address dealerAddress, address rewardPoolAddress) {
        if (tokenAddress == address(0) || dealerAddress == address(0) || rewardPoolAddress == address(0)) {
            revert InvalidRecipient();
        }
        token = ILandlordsToken(tokenAddress);
        dealer = dealerAddress;
        rewardPool = rewardPoolAddress;
        tokenUnit = 10 ** uint256(ILandlordsToken(tokenAddress).decimals());
        for (uint256 i = 1; i <= TOTAL_ROOMS; i++) {
            rooms[i].roundNumber = 1;
        }
    }

    function joinRoom(uint256 roomId) external validRoom(roomId) {
        Room storage room = rooms[roomId];
        RoomConfig memory cfg = _configOf(roomId);
        if (room.status != RoomStatus.Waiting) revert RoomNotOpen();
        if (room.playerCount >= ROOM_PLAYERS) revert RoomFull();
        if (players[roomId][msg.sender].addr != address(0) || userRoomIds[msg.sender] != 0) {
            revert AlreadyInRoom();
        }

        _safeTransferFrom(msg.sender, cfg.maxDeposit);
        players[roomId][msg.sender] = Player(msg.sender, cfg.maxDeposit);
        room.playerAddrs[room.playerCount] = msg.sender;
        room.playerCount++;
        room.escrow += cfg.maxDeposit;
        userRoomIds[msg.sender] = roomId;

        emit PlayerJoined(roomId, msg.sender, cfg.maxDeposit, room.roundNumber);
        if (room.playerCount == ROOM_PLAYERS) {
            room.status = RoomStatus.Locked;
            emit RoomLocked(roomId, room.roundNumber, room.escrow);
        }
    }

    /**
     * addrs 索引：
     * [0] 黑洞地址；
     * [1..winnerCount] 赢家地址，地主胜为1个，农民胜为2个；
     * 后续依次为 directCount 个直推地址和 indirectCount 个间推地址。
     *
     * values 索引：
     * [0..2] 三个链上座位的实际押注；
     * [3] winnerCount；[4] directCount；[5] indirectCount；
     * [6..] 依次为赢家金额、直推金额、间推金额，与 addrs[1..] 一一对应。
     */
    function settleRoom(
        uint256 roomId,
        address[] calldata addrs,
        uint256[] calldata values
    ) external onlyDealer validRoom(roomId) {
        Room storage room = rooms[roomId];
        if (room.status != RoomStatus.Locked) revert RoomNotLocked();
        _validateArrays(addrs, values);
        _validateWinners(roomId, addrs, values[3]);
        (uint256 totalBet, uint256 totalRefund) = _collectBetsAndRefunds(roomId, values);
        if (totalBet == 0 || totalBet % 100 != 0) revert InvalidBetTotal();
        _distributeSettlement(addrs, values, totalBet);

        uint256 totalPaid = totalRefund + totalBet;
        if (totalPaid != room.escrow) revert InvalidPayoutTotal();
        emit RoomSettled(roomId, room.roundNumber, totalBet, totalPaid);
        _resetRoom(roomId);
    }

    function refundRoom(uint256 roomId) external onlyDealer validRoom(roomId) {
        Room storage room = rooms[roomId];
        if (room.playerCount == 0) revert RoomNotOpen();
        uint256 totalRefunded;
        for (uint256 i = 0; i < room.playerCount; i++) {
            address player = room.playerAddrs[i];
            uint256 deposit = players[roomId][player].deposit;
            totalRefunded += deposit;
            _safeTransfer(player, deposit);
        }
        emit RoomRefunded(roomId, room.roundNumber, totalRefunded);
        _resetRoom(roomId);
    }

    /**
     * values: [status, roundNumber, escrow, playerCount, betUnit, maxDeposit, playerCapacity]
     * addrs: [player0, player1, player2]
     */
    function getRoomInfo(uint256 roomId)
        external
        view
        validRoom(roomId)
        returns (uint256[] memory values, address[] memory addrs)
    {
        Room storage room = rooms[roomId];
        RoomConfig memory cfg = _configOf(roomId);
        values = new uint256[](7);
        values[0] = uint256(room.status);
        values[1] = room.roundNumber;
        values[2] = room.escrow;
        values[3] = room.playerCount;
        values[4] = cfg.betUnit;
        values[5] = cfg.maxDeposit;
        values[6] = ROOM_PLAYERS;
        addrs = new address[](ROOM_PLAYERS);
        for (uint256 i = 0; i < ROOM_PLAYERS; i++) {
            addrs[i] = room.playerAddrs[i];
        }
    }

    /** values: [deposit]；flags: [joined]。 */
    function getPlayerInfo(uint256 roomId, address player)
        external
        view
        validRoom(roomId)
        returns (uint256[] memory values, bool[] memory flags)
    {
        Player storage item = players[roomId][player];
        values = new uint256[](1);
        values[0] = item.deposit;
        flags = new bool[](1);
        flags[0] = item.addr != address(0);
    }

    function getUserRoom(address user) external view returns (uint256 roomId, bool joined) {
        roomId = userRoomIds[user];
        joined = roomId != 0;
    }

    function _configOf(uint256 roomId) internal view returns (RoomConfig memory cfg) {
        if (roomId <= 9) {
            return RoomConfig(1_000 * tokenUnit, 20_000 * tokenUnit);
        }
        if (roomId <= 18) {
            return RoomConfig(3_000 * tokenUnit, 60_000 * tokenUnit);
        }
        return RoomConfig(5_000 * tokenUnit, 100_000 * tokenUnit);
    }

    function _validateArrays(address[] calldata addrs, uint256[] calldata values) internal pure {
        if (values.length < 7 || addrs.length < 2) revert InvalidArrayLength();
        uint256 mappedCount = values[3] + values[4] + values[5];
        if (addrs.length != mappedCount + 1 || values.length != mappedCount + 6) {
            revert InvalidArrayLength();
        }
    }

    function _validateWinners(uint256 roomId, address[] calldata addrs, uint256 winnerCount) internal view {
        if (winnerCount < 1 || winnerCount > 2) revert InvalidWinnerCount();
        for (uint256 i = 0; i < winnerCount; i++) {
            if (!_isRoomPlayer(roomId, addrs[i + 1])) revert InvalidWinner();
        }
    }

    function _distributeSettlement(
        address[] calldata addrs,
        uint256[] calldata values,
        uint256 totalBet
    ) internal {
        uint256 winnerCount = values[3];
        uint256 directCount = values[4];
        uint256 indirectCount = values[5];
        uint256 directStart = 6 + winnerCount;
        uint256 indirectStart = directStart + directCount;
        uint256 directTotal = _sumRange(values, directStart, directCount);
        uint256 indirectTotal = _sumRange(values, indirectStart, indirectCount);
        uint256 directTarget = totalBet * 3 / 100;
        uint256 indirectTarget = totalBet * 2 / 100;

        if (_sumRange(values, 6, winnerCount) != totalBet * 70 / 100
            || directTotal > directTarget
            || indirectTotal > indirectTarget) {
            revert InvalidRewardAmount();
        }

        _payMappedRecipients(addrs, values, winnerCount + directCount + indirectCount);
        uint256 missingReferral = directTarget - directTotal + indirectTarget - indirectTotal;
        _safeTransfer(addrs[0], totalBet * 10 / 100 + missingReferral);
        _depositReplenishReward(totalBet * 10 / 100);
        _depositRankReward(totalBet * 5 / 100);
    }

    function _payMappedRecipients(
        address[] calldata addrs,
        uint256[] calldata values,
        uint256 recipientCount
    ) internal {
        for (uint256 i = 0; i < recipientCount; i++) {
            if (addrs[i + 1] == address(0)) revert InvalidRecipient();
            if (values[i + 6] > 0) {
                _safeTransfer(addrs[i + 1], values[i + 6]);
            }
        }
    }

    function _collectBetsAndRefunds(uint256 roomId, uint256[] calldata values)
        internal
        returns (uint256 totalBet, uint256 totalRefund)
    {
        Room storage room = rooms[roomId];
        for (uint256 i = 0; i < ROOM_PLAYERS; i++) {
            address player = room.playerAddrs[i];
            uint256 deposit = players[roomId][player].deposit;
            if (values[i] == 0 || values[i] > deposit) revert InvalidBetAmount();
            totalBet += values[i];
            uint256 refundAmount = deposit - values[i];
            if (refundAmount > 0) {
                totalRefund += refundAmount;
                _safeTransfer(player, refundAmount);
            }
        }
    }

    function _isRoomPlayer(uint256 roomId, address player) internal view returns (bool) {
        return player != address(0) && players[roomId][player].addr != address(0);
    }

    function _sumRange(uint256[] calldata values, uint256 start, uint256 count)
        internal
        pure
        returns (uint256 total)
    {
        for (uint256 i = 0; i < count; i++) {
            total += values[start + i];
        }
    }

    function _depositRankReward(uint256 amount) internal {
        if (!token.approve(rewardPool, amount)) revert TokenTransferFailed();
        ILandlordsRewardPool(rewardPool).depositRankReward(amount);
    }

    function _depositReplenishReward(uint256 amount) internal {
        if (!token.approve(rewardPool, amount)) revert TokenTransferFailed();
        ILandlordsRewardPool(rewardPool).depositReplenishReward(amount);
    }

    function _safeTransferFrom(address from, uint256 amount) internal {
        if (amount == 0) revert TokenAmountMustBePositive();
        if (token.balanceOf(from) < amount) revert InsufficientTokenBalance();
        if (token.allowance(from, address(this)) < amount) revert InsufficientTokenAllowance();
        if (!token.transferFrom(from, address(this), amount)) revert TokenTransferFromFailed();
    }

    function _safeTransfer(address to, uint256 amount) internal {
        if (to == address(0)) revert InvalidRecipient();
        if (amount == 0) revert TokenAmountMustBePositive();
        if (token.balanceOf(address(this)) < amount) revert InsufficientContractTokenBalance();
        if (!token.transfer(to, amount)) revert TokenTransferFailed();
    }

    function _resetRoom(uint256 roomId) internal {
        Room storage room = rooms[roomId];
        for (uint256 i = 0; i < room.playerCount; i++) {
            address player = room.playerAddrs[i];
            delete players[roomId][player];
            delete userRoomIds[player];
        }
        delete room.playerAddrs;
        room.status = RoomStatus.Waiting;
        room.escrow = 0;
        room.playerCount = 0;
        room.roundNumber++;
        emit RoomReset(roomId, room.roundNumber);
    }
}
