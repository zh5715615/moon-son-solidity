// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGoldenFlowerRewardPool {
    function depositRankReward(uint256 amount) external;
    function depositReplenishReward(uint256 amount) external;
}

interface IGoldenFlowerToken {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

/**
 * @title GoldenFlower
 * @notice 三人场和五人场炸金花链上资金托管合约。
 *
 * 新版本职责边界：
 * 1. 链上只负责玩家进入房间时托管房间上限金额。
 * 2. 跟注、加注、看牌、弃牌、比牌全部由后端 dealer 链下处理。
 * 3. 后端按积分制计算实际输赢，最后由 dealer 调用 settleRoom 发奖励和退还剩余额度。
 * 4. 如果房间未完成或需要取消，dealer 可调用 refundRoom 原路退还已加入玩家的托管金额。
 *
 * 房间档位：
 * roomId  1-5  : 3 人场 | 底注 1,000 | 入房托管 30,000
 * roomId  6-10 : 3 人场 | 底注 1,000 | 入房托管 120,000
 * roomId 11-15 : 5 人场 | 底注 1,000 | 入房托管 50,000
 * roomId 16-20 : 5 人场 | 底注 1,000 | 入房托管 200,000
 */
contract GoldenFlower {

    error OnlyDealer();
    error InvalidRoomId();
    error RoomNotOpen();
    error RoomNotLocked();
    error RoomFull();
    error AlreadyInRoom();
    error PlayerNotInRoom();
    error InvalidArrayLength();
    error InvalidRecipient();
    error DuplicateRecipient();
    error InvalidPayoutTotal();
    error InvalidWinner();
    error InvalidBetAmount();
    error InvalidBetTotal();
    error InvalidPoolAddress();
    error InvalidReferralAmount();
    error TokenAmountMustBePositive();
    error InsufficientTokenBalance();
    error InsufficientTokenAllowance();
    error TokenTransferFromFailed();
    error InvalidTokenReceiver();
    error InsufficientContractTokenBalance();
    error TokenTransferFailed();

    uint256 public constant TOTAL_ROOMS = 20;
    // 最大房间容量；具体房间是 3 人场还是 5 人场，由 _configOf(roomId) 决定。
    uint256 public constant ROOM_PLAYERS = 5;

    IGoldenFlowerToken public immutable token;
    address public immutable dealer;
    address public immutable rewardPool;
    uint256 public immutable tokenUnit;

    enum RoomStatus { Waiting, Locked }

    struct RoomConfig {
        // 链下积分单位，当前所有房型均为 1K。
        uint256 betUnit;

        // 玩家入房时一次性托管的上限金额：30K / 120K / 50K / 200K。
        uint256 maxDeposit;

        // 房间满员人数，仅允许 3 或 5。
        uint256 playerCapacity;
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
        address[5] playerAddrs;
    }

    mapping(uint256 => Room) private rooms;
    mapping(uint256 => mapping(address => Player)) private players;

    // 用户当前所在房间号。0 表示不在任何房间中。
    mapping(address => uint256) private userRoomIds;

    /**
     * @notice 玩家加入房间并托管上限金额。
     */
    event PlayerJoined(uint256 indexed roomId, address indexed player, uint256 deposit, uint256 round);

    /**
     * @notice 房间达到当前房型人数上限，链上资金已锁定，后端可以开始链下游戏。
     */
    event RoomLocked(uint256 indexed roomId, uint256 round, uint256 escrow);

    /**
     * @notice dealer 完成结算。
     */
    event RoomSettled(uint256 indexed roomId, uint256 round, uint256 totalBet, uint256 totalPaid);

    /**
     * @notice dealer 取消房间，退还所有已加入玩家的托管金额。
     */
    event RoomRefunded(uint256 indexed roomId, uint256 round, uint256 totalRefunded);

    /**
     * @notice 房间重置，可以进入下一局。
     */
    event RoomReset(uint256 indexed roomId, uint256 newRound);

    modifier onlyDealer() {
        if (msg.sender != dealer) revert OnlyDealer();
        _;
    }

    modifier validRoom(uint256 roomId) {
        if (roomId < 1 || roomId > TOTAL_ROOMS) revert InvalidRoomId();
        _;
    }

    constructor(address _token, address _dealer, address _rewardPool) {
        if (_token == address(0)) revert InvalidTokenReceiver();
        if (_dealer == address(0)) revert InvalidRecipient();
        if (_rewardPool == address(0)) revert InvalidPoolAddress();
        token = IGoldenFlowerToken(_token);
        dealer = _dealer;
        rewardPool = _rewardPool;
        tokenUnit = 10 ** uint256(IGoldenFlowerToken(_token).decimals());

        for (uint256 i = 1; i <= TOTAL_ROOMS; i++) {
            rooms[i].status = RoomStatus.Waiting;
            rooms[i].roundNumber = 1;
        }
    }

    /**
     * @notice 根据 roomId 返回房间配置。
     */
    function _configOf(uint256 roomId) internal view returns (RoomConfig memory cfg) {
        if (roomId < 1 || roomId > TOTAL_ROOMS) revert InvalidRoomId();
        if (roomId <= 5) {
            cfg = RoomConfig({ betUnit: 1_000 * tokenUnit, maxDeposit: 30_000 * tokenUnit, playerCapacity: 3 });
        } else if (roomId <= 10) {
            cfg = RoomConfig({ betUnit: 1_000 * tokenUnit, maxDeposit: 120_000 * tokenUnit, playerCapacity: 3 });
        } else if (roomId <= 15) {
            cfg = RoomConfig({ betUnit: 1_000 * tokenUnit, maxDeposit: 50_000 * tokenUnit, playerCapacity: 5 });
        } else {
            cfg = RoomConfig({ betUnit: 1_000 * tokenUnit, maxDeposit: 200_000 * tokenUnit, playerCapacity: 5 });
        }
    }

    /**
     * @notice 玩家进入房间。
     *
     * 玩家需要先 approve 本合约 maxDeposit。
     * 入房时直接托管该房间上限金额，不再链上跟注/加注。
     */
    function joinRoom(uint256 roomId) external validRoom(roomId) {
        Room storage room = rooms[roomId];
        RoomConfig memory cfg = _configOf(roomId);
        if (room.status != RoomStatus.Waiting) revert RoomNotOpen();
        if (room.playerCount >= cfg.playerCapacity) revert RoomFull();
        if (players[roomId][msg.sender].addr != address(0)) revert AlreadyInRoom();
        if (userRoomIds[msg.sender] != 0) revert AlreadyInRoom();

        _safeTransferFrom(msg.sender, cfg.maxDeposit);

        players[roomId][msg.sender] = Player({
            addr: msg.sender,
            deposit: cfg.maxDeposit
        });

        room.playerAddrs[room.playerCount] = msg.sender;
        room.playerCount += 1;
        room.escrow += cfg.maxDeposit;
        userRoomIds[msg.sender] = roomId;

        emit PlayerJoined(roomId, msg.sender, cfg.maxDeposit, room.roundNumber);

        if (room.playerCount == cfg.playerCapacity) {
            room.status = RoomStatus.Locked;
            emit RoomLocked(roomId, room.roundNumber, room.escrow);
        }
    }

    /**
     * @notice dealer 结算房间。
     *
     * 后端链下完成跟注、加注、看牌、弃牌、比牌和积分计算后调用。
     *
     * values 索引含义：
     * [0..4] = 五个座位的实际押注，必须和 getRoomInfo 返回的 addrs 对齐；
     *          3 人房的 [3]、[4] 固定补 0。
     * [5] = directCount，直推奖励地址数量
     * [6] = indirectCount，间推奖励地址数量
     * [7..] = 先放 directCount 个直推金额，再放 indirectCount 个间推金额
     *
     * poolAddrs 索引含义：
     * [0] = blackHoleAddress，销毁/黑洞地址，获得押注总额 10%
     *
     * 排名奖池和权益回补池不再由入参传入，统一进入 rewardPool 共享奖励池：
     * rewardPool.rankPoolBalance 增加押注总额 5%
     * rewardPool.replenishPoolBalance 增加押注总额 10%
     *
     * rewardUsers / rewardAmounts 索引一一对应：
     * rewardUsers[0 ... rewardCounts[0]-1] = 直推用户地址
     * rewardAmounts[0 ... rewardCounts[0]-1] = 直推用户金额，合计必须等于押注总额 3%
     * rewardUsers[rewardCounts[0] ... rewardCounts[0]+rewardCounts[1]-1] = 间推用户地址
     * rewardAmounts[rewardCounts[0] ... rewardCounts[0]+rewardCounts[1]-1] = 间推用户金额，合计必须等于押注总额 2%
     *
     * rewardCounts 索引含义：
     * [0] = directCount，直推奖励数量
     * [1] = indirectCount，间推奖励数量
     *
     * 合约自动执行：
     * 1. 每个玩家退还 deposit - playerBets[i]。
     * 2. 押注总额 70% 给 winner。
     * 3. 押注总额 10% 给黑洞地址。
     * 4. 押注总额 10% 给权益回补池。
     * 5. 押注总额 5% 给日结排名奖池。
     * 6. 押注总额 3% 按 rewardUsers/rewardAmounts 前 directCount 个发放。
     * 7. 押注总额 2% 按 rewardUsers/rewardAmounts 后 indirectCount 个发放。
     */
    function settleRoom(
        uint256 roomId,
        address[] calldata addrs,
        uint256[] calldata values
    ) external onlyDealer validRoom(roomId) {
        Room storage room = rooms[roomId];
        if (room.status != RoomStatus.Locked) revert RoomNotLocked();
        _validateSettlementParams(addrs, values);
        if (!_isRoomPlayer(roomId, addrs[0])) revert InvalidWinner();

        uint256 round = room.roundNumber;

        (uint256 totalBet, uint256 totalRefund) = _collectBetsAndRefunds(roomId, values);

        if (totalBet == 0 || totalBet % 100 != 0) revert InvalidBetTotal();
        _validateReferralTotals(totalBet, values);
        _payBaseSettlement(totalBet, addrs[0], addrs[1]);
        _payMappedRecipients(addrs, values);

        uint256 totalPaid = totalRefund + totalBet;
        if (totalPaid != room.escrow) revert InvalidPayoutTotal();

        emit RoomSettled(roomId, round, totalBet, totalPaid);
        _resetRoom(roomId);
    }

    /**
     * @notice dealer 取消房间并退还已加入玩家的托管金额。
     *
     * 适用场景：
     * 1. 房间未达到当前房型人数上限，游戏无法开始。
     * 2. 后端异常，需要取消本局。
     *
     * 如果房间已满且正常完成链下结算，应调用 settleRoom，而不是 refundRoom。
     */
    function refundRoom(uint256 roomId) external onlyDealer validRoom(roomId) {
        Room storage room = rooms[roomId];
        if (room.playerCount == 0) revert RoomNotOpen();

        uint256 totalRefunded;
        uint256 round = room.roundNumber;
        for (uint256 i = 0; i < room.playerCount; i++) {
            address player = room.playerAddrs[i];
            uint256 deposit = players[roomId][player].deposit;
            if (deposit > 0) {
                totalRefunded += deposit;
                _safeTransfer(player, deposit);
            }
        }

        emit RoomRefunded(roomId, round, totalRefunded);
        _resetRoom(roomId);
    }

    /**
     * @notice 查询房间信息。
     *
     * values 索引含义：
     * [0] = status，0=Waiting, 1=Locked
     * [1] = roundNumber，当前局号
     * [2] = escrow，当前房间托管总金额
     * [3] = playerCount，当前玩家数量
     * [4] = betUnit，链下积分单位
     * [5] = maxDeposit，单个玩家入房托管上限
     * [6] = playerCapacity，房间人数上限，值为 3 或 5
     *
     * addrs 索引含义：
     * [0] = player0，第 1 个加入的玩家
     * [1] = player1，第 2 个加入的玩家
     * [2] = player2，第 3 个加入的玩家
     * [3] = player3，第 4 个加入的玩家，仅 5 人房使用
     * [4] = player4，第 5 个加入的玩家，仅 5 人房使用
     */
    function getRoomInfo(uint256 roomId)
    external
    view
    validRoom(roomId)
    returns (
        uint256[] memory values,
        address[] memory addrs
    )
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
        values[6] = cfg.playerCapacity;

        addrs = new address[](cfg.playerCapacity);
        for (uint256 i = 0; i < cfg.playerCapacity; i++) {
            addrs[i] = room.playerAddrs[i];
        }
    }

    /**
     * @notice 查询玩家在房间内的托管信息。
     *
     * values 索引含义：
     * [0] = deposit，玩家本局托管金额
     *
     * flags 索引含义：
     * [0] = joined，玩家是否已加入该房间
     */
    function getPlayerInfo(uint256 roomId, address player)
    external
    view
    validRoom(roomId)
    returns (
        uint256[] memory values,
        bool[] memory flags
    )
    {
        Player storage p = players[roomId][player];

        values = new uint256[](1);
        values[0] = p.deposit;

        flags = new bool[](1);
        flags[0] = p.addr != address(0);
    }

    /**
     * @notice 根据用户查询其当前所在房间。
     *
     * 返回值：
     * roomId = 用户当前房间号，0 表示不在任何房间中
     * joined = 用户是否正在某个房间中
     */
    function getUserRoom(address user)
    external
    view
    returns (
        uint256 roomId,
        bool joined
    )
    {
        roomId = userRoomIds[user];
        joined = roomId != 0;
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
        room.roundNumber += 1;

        emit RoomReset(roomId, room.roundNumber);
    }

    function _isRoomPlayer(uint256 roomId, address player) internal view returns (bool) {
        if (player == address(0)) return false;
        return players[roomId][player].addr != address(0);
    }

    /**
     * @dev 验证结算数组。values[0..4] 固定对应五个座位的押注，
     *      3 人房的 values[3]、values[4] 必须补 0；values[5]、values[6]
     *      分别为直推和间推收款地址数量，values[7..] 为对应奖励金额。
     */
    function _validateSettlementParams(
        address[] calldata addrs,    // 地址数组，包含接收方地址
        uint256[] calldata values    // 数值数组，包含结算金额和数量参数
    ) internal pure {                // 内部纯函数，不修改状态，且只能在内部调用
        if (addrs.length < 2) revert InvalidArrayLength();    // 检查地址数组长度是否小于2
        if (values.length < 7) revert InvalidArrayLength();
        if (addrs.length != values[5] + values[6] + 2) revert InvalidArrayLength();
        if (values.length != values[5] + values[6] + 7) revert InvalidArrayLength();
    }

    function _collectBetsAndRefunds(
        uint256 roomId,
        uint256[] calldata values
    ) internal returns (uint256 totalBet, uint256 totalRefund) {
        Room storage room = rooms[roomId];

        for (uint256 i = 0; i < room.playerCount; i++) {
            address player = room.playerAddrs[i];
            uint256 deposit = players[roomId][player].deposit;
            if (values[i] > deposit) revert InvalidBetAmount();

            totalBet += values[i];
            if (deposit > values[i]) {
                uint256 refundAmount = deposit - values[i];
                totalRefund += refundAmount;
                _safeTransfer(player, refundAmount);
            }
        }
    }

    function _validateReferralTotals(
        uint256 totalBet,
        uint256[] calldata values
    ) internal pure {
        if (_sumRange(values, 7, values[5]) != totalBet * 3 / 100) revert InvalidReferralAmount();
        if (_sumRange(values, 7 + values[5], values[6]) != totalBet * 2 / 100) revert InvalidReferralAmount();
    }

    function _payBaseSettlement(
        uint256 totalBet,
        address winner,
        address blackHole
    ) internal {
        _safeTransfer(winner, totalBet * 70 / 100);
        _safeTransfer(blackHole, totalBet * 10 / 100);
        _depositReplenishReward(totalBet * 10 / 100);
        _depositRankReward(totalBet * 5 / 100);
    }

    function _hasDuplicateRecipient(address[] calldata recipients, uint256 index) internal pure returns (bool) {
        address current = recipients[index];
        for (uint256 i = 2; i < index; i++) {
            if (recipients[i] == current) return true;
        }
        return false;
    }

    function _depositRankReward(uint256 amount) internal {
        if (!token.approve(rewardPool, amount)) revert TokenTransferFailed();
        IGoldenFlowerRewardPool(rewardPool).depositRankReward(amount);
    }

    function _depositReplenishReward(uint256 amount) internal {
        if (!token.approve(rewardPool, amount)) revert TokenTransferFailed();
        IGoldenFlowerRewardPool(rewardPool).depositReplenishReward(amount);
    }

    function _sumRange(
        uint256[] calldata amounts,
        uint256 start,
        uint256 count
    ) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < count; i++) {
            total += amounts[start + i];
        }
    }

    function _payMappedRecipients(address[] calldata addrs, uint256[] calldata values) internal {
        for (uint256 i = 0; i < values[5] + values[6]; i++) {
            if (addrs[i + 2] == address(0)) revert InvalidRecipient();
            if (values[i + 7] > 0) {
                _safeTransfer(addrs[i + 2], values[i + 7]);
            }
        }
    }

    /**
     * @notice 检查玩家余额和授权额度。
     */
    function _requireTokenFunds(address from, uint256 amount) internal view {
        if (amount == 0) revert TokenAmountMustBePositive();
        if (token.balanceOf(from) < amount) revert InsufficientTokenBalance();
        if (token.allowance(from, address(this)) < amount) revert InsufficientTokenAllowance();
    }

    function _safeTransferFrom(address from, uint256 amount) internal {
        _requireTokenFunds(from, amount);
        if (!token.transferFrom(from, address(this), amount)) revert TokenTransferFromFailed();
    }

    function _safeTransfer(address to, uint256 amount) internal {
        if (to == address(0)) revert InvalidTokenReceiver();
        if (amount == 0) revert TokenAmountMustBePositive();
        if (token.balanceOf(address(this)) < amount) revert InsufficientContractTokenBalance();
        if (!token.transfer(to, amount)) revert TokenTransferFailed();
    }
}
