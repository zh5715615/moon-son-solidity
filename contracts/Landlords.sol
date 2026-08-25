// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./pricing/PancakeV2UsdtQuote.sol";

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
 * roomId 1-12：3 人场，入场费统一为 200（2.00 USDT）。
 */
contract Landlords is PancakeV2UsdtQuote {
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
    error TokenAmountMustBePositive();
    error InsufficientTokenBalance();
    error InsufficientTokenAllowance();
    error TokenTransferFromFailed();
    error TokenTransferFailed();
    error InsufficientContractTokenBalance();

    uint256 public constant TOTAL_ROOMS = 12;
    uint256 public constant ROOM_PLAYERS = 3;
    uint256 public constant ENTRY_FEE_USDT_CENTS = 200;
    uint256 public constant POINTS_PER_USDT_CENT = 1000;

    ILandlordsToken public immutable yion;
    address public immutable dealer;
    address public immutable rewardPool;
    uint256 public immutable yionUnit;

    enum RoomStatus { Waiting, Locked }

    struct RoomConfig {
        uint256 betUnit;
        uint256 maxDeposit;
    }

    struct Player {
        address addr;
        uint256 deposit;
        uint256 usdtDeposit;
    }

    struct Room {
        RoomStatus status;
        uint256 roundNumber;
        uint256 escrow;
        uint256 playerCount;
        address[3] playerAddrs;
    }

    struct SettlementAmounts {
        uint256 winner;
        uint256 direct;
        uint256 indirect;
        uint256 replenish;
        uint256 rank;
        uint256 blackHole;
        uint256 recipientCount;
    }

    mapping(uint256 => Room) private rooms;
    mapping(uint256 => mapping(address => Player)) private players;
    mapping(address => uint256) private userRoomIds;

    event PlayerJoined(uint256 indexed roomId, address indexed player, uint256 deposit, uint256 round);
    event UsdtPriceQuoted(address indexed player, uint256 usdtPriceCents, uint256 tokenAmount);
    event RoomLocked(uint256 indexed roomId, uint256 round, uint256 escrow);
    event RoomSettled(uint256 indexed roomId, uint256 round, uint256 totalBet, uint256 totalPaid);
    event SettlementModeSelected(
        uint256 indexed roomId,
        bool usdtMode,
        uint256 escrowToken,
        uint256 quotedTokenRequired,
        uint256 paidToken
    );
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

    constructor(address yionAddress, address dealerAddress, address rewardPoolAddress) {
        if (yionAddress == address(0) || dealerAddress == address(0) || rewardPoolAddress == address(0)) {
            revert InvalidRecipient();
        }
        yion = ILandlordsToken(yionAddress);
        dealer = dealerAddress;
        rewardPool = rewardPoolAddress;
        yionUnit = 10 ** uint256(ILandlordsToken(yionAddress).decimals());
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

        uint256 tokenDeposit = _quoteTokenAmount(cfg.maxDeposit);
        _safeTransferFrom(msg.sender, tokenDeposit);
        players[roomId][msg.sender] = Player(msg.sender, tokenDeposit, cfg.maxDeposit);
        room.playerAddrs[room.playerCount] = msg.sender;
        room.playerCount++;
        room.escrow += tokenDeposit;
        userRoomIds[msg.sender] = roomId;

        emit UsdtPriceQuoted(msg.sender, cfg.maxDeposit, tokenDeposit);
        emit PlayerJoined(roomId, msg.sender, tokenDeposit, room.roundNumber);
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
     * [0..2] 三个链上座位的实际押注（USDT 美分）；
     * [3] winnerCount；[4] directCount；[5] indirectCount；
     * [6..] 依次为赢家、直推、间推的 USDT 美分金额，与 addrs[1..] 一一对应。
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
        uint256 totalBetUsdtCents = _validateAndSumBets(roomId, values);
        if (totalBetUsdtCents == 0) revert InvalidBetTotal();
        SettlementAmounts memory amount = _calculateSettlement(values, totalBetUsdtCents);
        uint256 totalEscrowUsdtCents = _roomUsdtEscrow(roomId);
        uint256 quotedTokenRequired = _quoteTokenAmount(totalEscrowUsdtCents);
        // 结算使用入场时实际锁定的 token 总额，避免结算时价格变化造成差额滞留。
        bool usdtMode = false;
        uint256 settlementToken = room.escrow;
        uint256 totalPaidToken = _executeSettlement(
            roomId,
            addrs,
            values,
            amount.recipientCount,
            totalBetUsdtCents,
            totalEscrowUsdtCents,
            settlementToken
        );

        emit SettlementModeSelected(roomId, usdtMode, room.escrow, quotedTokenRequired, totalPaidToken);
        emit RoomSettled(roomId, room.roundNumber, totalBetUsdtCents, totalPaidToken);
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
     * values: [status, roundNumber, escrow, playerCount, betUnitUsdtCents,
     *          maxDepositUsdtCents, playerCapacity]
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

    /** values: [tokenDeposit, usdtDepositCents]；flags: [joined]。 */
    function getPlayerInfo(uint256 roomId, address player)
        external
        view
        validRoom(roomId)
        returns (uint256[] memory values, bool[] memory flags)
    {
        Player storage item = players[roomId][player];
        values = new uint256[](2);
        values[0] = item.deposit;
        values[1] = item.usdtDeposit;
        flags = new bool[](1);
        flags[0] = item.addr != address(0);
    }

    function getUserRoom(address user) external view returns (uint256 roomId, bool joined) {
        roomId = userRoomIds[user];
        joined = roomId != 0;
    }

    function _configOf(uint256 roomId) internal pure returns (RoomConfig memory) {
        if (roomId < 1 || roomId > TOTAL_ROOMS) revert InvalidRoomId();
        return RoomConfig(ENTRY_FEE_USDT_CENTS, ENTRY_FEE_USDT_CENTS);
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

    function _executeSettlement(
        uint256 roomId,
        address[] calldata addrs,
        uint256[] calldata values,
        uint256 recipientCount,
        uint256 totalBetUsdtCents,
        uint256 totalEscrowUsdtCents,
        uint256 settlementToken
    ) internal returns (uint256 paidToken) {
        uint256 refundToken = _refundPlayers(
            roomId,
            values,
            totalEscrowUsdtCents,
            settlementToken
        );
        uint256 totalBetToken = settlementToken - refundToken;
        uint256 mappedToken;
        for (uint256 i = 0; i < recipientCount; i++) {
            if (addrs[i + 1] == address(0)) revert InvalidRecipient();
            uint256 tokenAmount = totalBetToken * values[i + 6] / totalBetUsdtCents;
            if (tokenAmount > 0) {
                _safeTransfer(addrs[i + 1], tokenAmount);
                mappedToken += tokenAmount;
            }
        }
        uint256 replenishToken = totalBetToken * 2 / 100;
        uint256 rankToken = totalBetToken * 2 / 100;
        uint256 blackHoleToken = totalBetToken - mappedToken - replenishToken - rankToken;
        _safeTransfer(addrs[0], blackHoleToken);
        _depositReplenishReward(replenishToken);
        _depositRankReward(rankToken);
        return settlementToken;
    }

    function _calculateSettlement(uint256[] calldata values, uint256 totalBet)
        internal
        pure
        returns (SettlementAmounts memory amount)
    {
        uint256 winnerCount = values[3];
        uint256 directCount = values[4];
        uint256 indirectCount = values[5];
        uint256 directStart = 6 + winnerCount;
        uint256 indirectStart = directStart + directCount;
        amount.direct = _sumRange(values, directStart, directCount);
        amount.indirect = _sumRange(values, indirectStart, indirectCount);
        amount.winner = totalBet * 90 / 100;
        amount.replenish = totalBet * 2 / 100;
        amount.rank = totalBet * 2 / 100;
        amount.recipientCount = winnerCount + directCount + indirectCount;
        uint256 directTarget = totalBet * 2 / 100;
        uint256 indirectTarget = totalBet * 1 / 100;

        if (_sumRange(values, 6, winnerCount) != amount.winner
            || amount.direct > directTarget
            || amount.indirect > indirectTarget) {
            revert InvalidRewardAmount();
        }

        // The black-hole allocation absorbs missing referrals and integer-division dust,
        // so the full escrow is always distributed even for arbitrary quote amounts.
        amount.blackHole = totalBet
            - amount.winner
            - amount.direct
            - amount.indirect
            - amount.replenish
            - amount.rank;
    }

    function _validateAndSumBets(uint256 roomId, uint256[] calldata values)
        internal
        view
        returns (uint256 totalBetUsdtCents)
    {
        Room storage room = rooms[roomId];
        for (uint256 i = 0; i < ROOM_PLAYERS; i++) {
            address player = room.playerAddrs[i];
            uint256 usdtDeposit = players[roomId][player].usdtDeposit;
            if (values[i] == 0 || values[i] > usdtDeposit * POINTS_PER_USDT_CENT) revert InvalidBetAmount();
            totalBetUsdtCents += values[i];
        }
    }

    function _refundPlayers(
        uint256 roomId,
        uint256[] calldata values,
        uint256 totalEscrowUsdtCents,
        uint256 settlementToken
    )
        internal
        returns (uint256 totalRefundToken)
    {
        Room storage room = rooms[roomId];
        for (uint256 i = 0; i < ROOM_PLAYERS; i++) {
            address playerAddress = room.playerAddrs[i];
            Player storage player = players[roomId][playerAddress];
            uint256 depositPoints = player.usdtDeposit * POINTS_PER_USDT_CENT;
            uint256 refundPoints = depositPoints - values[i];
            uint256 totalEscrowPoints = totalEscrowUsdtCents * POINTS_PER_USDT_CENT;
            uint256 refundToken = settlementToken * refundPoints / totalEscrowPoints;
            totalRefundToken += refundToken;
            if (refundToken > 0) _safeTransfer(playerAddress, refundToken);
        }
    }

    function _roomUsdtEscrow(uint256 roomId) internal view returns (uint256 totalUsdtCents) {
        Room storage room = rooms[roomId];
        for (uint256 i = 0; i < ROOM_PLAYERS; i++) {
            totalUsdtCents += players[roomId][room.playerAddrs[i]].usdtDeposit;
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
        if (!yion.approve(rewardPool, amount)) revert TokenTransferFailed();
        ILandlordsRewardPool(rewardPool).depositRankReward(amount);
    }

    function _depositReplenishReward(uint256 amount) internal {
        if (!yion.approve(rewardPool, amount)) revert TokenTransferFailed();
        ILandlordsRewardPool(rewardPool).depositReplenishReward(amount);
    }

    function _safeTransferFrom(address from, uint256 amount) internal {
        if (amount == 0) revert TokenAmountMustBePositive();
        if (yion.balanceOf(from) < amount) revert InsufficientTokenBalance();
        if (yion.allowance(from, address(this)) < amount) revert InsufficientTokenAllowance();
        if (!yion.transferFrom(from, address(this), amount)) revert TokenTransferFromFailed();
    }

    function _safeTransfer(address to, uint256 amount) internal {
        if (to == address(0)) revert InvalidRecipient();
        if (amount == 0) revert TokenAmountMustBePositive();
        if (yion.balanceOf(address(this)) < amount) revert InsufficientContractTokenBalance();
        if (!yion.transfer(to, amount)) revert TokenTransferFailed();
    }

    function _paymentToken() internal view override returns (address) {
        return address(yion);
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
