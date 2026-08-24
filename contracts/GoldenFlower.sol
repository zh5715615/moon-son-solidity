// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./pricing/PancakeV2UsdtQuote.sol";

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
 * roomId  1-10 : 3 人场 | 入场费 200（2.00 USDT）
 * roomId 11-20 : 5 人场 | 入场费 400（4.00 USDT）
 */
contract GoldenFlower is PancakeV2UsdtQuote {

    error OnlyDealer();
    error InvalidRoomId();
    error RoomNotOpen();
    error RoomNotLocked();
    error RoomFull();
    error AlreadyInRoom();
    error InvalidArrayLength();
    error InvalidRecipient();
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
    uint256 public constant FIVE_PLAYER_LOW_ENTRY_FEE_USDT_CENTS = 200;
    uint256 public constant FIVE_PLAYER_HIGH_ENTRY_FEE_USDT_CENTS = 400;
    uint256 public constant POINTS_PER_USDT_CENT = 10000;
    IGoldenFlowerToken public immutable yion;
    address public immutable dealer;
    address public immutable rewardPool;
    uint256 public immutable yionUnit;

    enum RoomStatus { Waiting, Locked }

    struct RoomConfig {
        // 链下积分单位，与当前房型入场费保持一致。
        uint256 betUnit;

        // 玩家入房时一次性托管的金额：3 人房 2.00 USDT，5 人房 4.00 USDT。
        uint256 maxDeposit;

        // 房间满员人数，仅允许 3 或 5。
        uint256 playerCapacity;
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
    event UsdtPriceQuoted(address indexed player, uint256 usdtPriceCents, uint256 tokenAmount);

    /**
     * @notice 房间达到当前房型人数上限，链上资金已锁定，后端可以开始链下游戏。
     */
    event RoomLocked(uint256 indexed roomId, uint256 round, uint256 escrow);

    /**
     * @notice dealer 完成结算。
     */
    event RoomSettled(uint256 indexed roomId, uint256 round, uint256 totalBet, uint256 totalPaid);
    event SettlementModeSelected(
        uint256 indexed roomId,
        bool usdtMode,
        uint256 escrowToken,
        uint256 quotedTokenRequired,
        uint256 paidToken
    );

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

    constructor(address _yion, address _dealer, address _rewardPool) {
        if (_yion == address(0)) revert InvalidTokenReceiver();
        if (_dealer == address(0)) revert InvalidRecipient();
        if (_rewardPool == address(0)) revert InvalidPoolAddress();
        yion = IGoldenFlowerToken(_yion);
        dealer = _dealer;
        rewardPool = _rewardPool;
        yionUnit = 10 ** uint256(IGoldenFlowerToken(_yion).decimals());

        for (uint256 i = 1; i <= TOTAL_ROOMS; i++) {
            rooms[i].roundNumber = 1;
        }
    }

    /**
     * @notice 根据 roomId 返回房间配置。
     */
    function _configOf(uint256 roomId) internal pure returns (RoomConfig memory cfg) {
        if (roomId < 1 || roomId > TOTAL_ROOMS) revert InvalidRoomId();
        uint256 playerCapacity = 5;
        uint256 entryFee = roomId <= 10
            ? FIVE_PLAYER_LOW_ENTRY_FEE_USDT_CENTS
            : FIVE_PLAYER_HIGH_ENTRY_FEE_USDT_CENTS;
        cfg = RoomConfig({
            betUnit: entryFee,
            maxDeposit: entryFee,
            playerCapacity: playerCapacity
        });
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

        uint256 tokenDeposit = _quoteTokenAmount(cfg.maxDeposit);
        _safeTransferFrom(msg.sender, tokenDeposit);

        players[roomId][msg.sender] = Player({
            addr: msg.sender,
            deposit: tokenDeposit,
            usdtDeposit: cfg.maxDeposit
        });

        room.playerAddrs[room.playerCount] = msg.sender;
        room.playerCount += 1;
        room.escrow += tokenDeposit;
        userRoomIds[msg.sender] = roomId;

        emit UsdtPriceQuoted(msg.sender, cfg.maxDeposit, tokenDeposit);
        emit PlayerJoined(roomId, msg.sender, tokenDeposit, room.roundNumber);

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
     * [0..4] = 五个座位的实际押注（USDT 美分），必须和 getRoomInfo 返回的 addrs 对齐；
     *          3 人房的 [3]、[4] 固定补 0。
     * [5] = directCount，直推奖励地址数量
     * [6] = indirectCount，间推奖励地址数量
     * [7..] = 先放 directCount 个直推 USDT 美分金额，再放 indirectCount 个间推 USDT 美分金额
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

        uint256 totalBetUsdtCents = _validateAndSumBets(roomId, values);

        if (totalBetUsdtCents == 0) revert InvalidBetTotal();
        _validateReferralTotals(totalBetUsdtCents, values);
        uint256 totalEscrowUsdtCents = _roomUsdtEscrow(roomId);
        uint256 quotedTokenRequired = _quoteTokenAmount(totalEscrowUsdtCents);
        bool usdtMode = quotedTokenRequired <= room.escrow;
        uint256 settlementToken = usdtMode ? quotedTokenRequired : room.escrow;
        uint256 totalPaidToken = _executeSettlement(
            roomId,
            addrs,
            values,
            totalBetUsdtCents,
            totalEscrowUsdtCents,
            settlementToken
        );

        emit SettlementModeSelected(roomId, usdtMode, room.escrow, quotedTokenRequired, totalPaidToken);
        emit RoomSettled(roomId, round, totalBetUsdtCents, totalPaidToken);
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
     * [6] = playerCapacity，房间人数上限，固定为 5
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
     * [0] = tokenDeposit；[1] = usdtDepositCents
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

        values = new uint256[](2);
        values[0] = p.deposit;
        values[1] = p.usdtDeposit;

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

    function _validateAndSumBets(
        uint256 roomId,
        uint256[] calldata values
    ) internal view returns (uint256 totalBetUsdtCents) {
        Room storage room = rooms[roomId];

        for (uint256 i = 0; i < room.playerCount; i++) {
            address player = room.playerAddrs[i];
            uint256 usdtDeposit = players[roomId][player].usdtDeposit;
            if (values[i] > usdtDeposit * POINTS_PER_USDT_CENT) revert InvalidBetAmount();

            totalBetUsdtCents += values[i];
        }
    }

    function _executeSettlement(
        uint256 roomId,
        address[] calldata addrs,
        uint256[] calldata values,
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
        _distributeBetSettlement(addrs, values, totalBetUsdtCents, totalBetToken);
        return settlementToken;
    }

    function _distributeBetSettlement(
        address[] calldata addrs,
        uint256[] calldata values,
        uint256 totalBetUsdtCents,
        uint256 totalBetToken
    ) internal {
        uint256 winnerToken = totalBetToken * 90 / 100;
        uint256 replenishToken = totalBetToken * 2 / 100;
        uint256 rankToken = totalBetToken * 2 / 100;
        uint256 mappedToken;
        for (uint256 i = 0; i < values[5] + values[6]; i++) {
            if (addrs[i + 2] == address(0)) revert InvalidRecipient();
            uint256 tokenAmount = totalBetToken * values[i + 7] / totalBetUsdtCents;
            if (tokenAmount > 0) {
                _safeTransfer(addrs[i + 2], tokenAmount);
                mappedToken += tokenAmount;
            }
        }
        uint256 blackHoleToken = totalBetToken - winnerToken - replenishToken - rankToken - mappedToken;
        _safeTransfer(addrs[0], winnerToken);
        _safeTransfer(addrs[1], blackHoleToken);
        _depositReplenishReward(replenishToken);
        _depositRankReward(rankToken);
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
        for (uint256 i = 0; i < room.playerCount; i++) {
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
        for (uint256 i = 0; i < room.playerCount; i++) {
            totalUsdtCents += players[roomId][room.playerAddrs[i]].usdtDeposit;
        }
    }

    function _validateReferralTotals(
        uint256 totalBet,
        uint256[] calldata values
    ) internal pure {
        if (_sumRange(values, 7, values[5]) != totalBet * 2 / 100) revert InvalidReferralAmount();
        if (_sumRange(values, 7 + values[5], values[6]) != totalBet * 1 / 100) revert InvalidReferralAmount();
    }

    function _depositRankReward(uint256 amount) internal {
        if (!yion.approve(rewardPool, amount)) revert TokenTransferFailed();
        IGoldenFlowerRewardPool(rewardPool).depositRankReward(amount);
    }

    function _depositReplenishReward(uint256 amount) internal {
        if (!yion.approve(rewardPool, amount)) revert TokenTransferFailed();
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

    /**
     * @notice 检查玩家余额和授权额度。
     */
    function _requireTokenFunds(address from, uint256 amount) internal view {
        if (amount == 0) revert TokenAmountMustBePositive();
        if (yion.balanceOf(from) < amount) revert InsufficientTokenBalance();
        if (yion.allowance(from, address(this)) < amount) revert InsufficientTokenAllowance();
    }

    function _safeTransferFrom(address from, uint256 amount) internal {
        _requireTokenFunds(from, amount);
        if (!yion.transferFrom(from, address(this), amount)) revert TokenTransferFromFailed();
    }

    function _safeTransfer(address to, uint256 amount) internal {
        if (to == address(0)) revert InvalidTokenReceiver();
        if (amount == 0) revert TokenAmountMustBePositive();
        if (yion.balanceOf(address(this)) < amount) revert InsufficientContractTokenBalance();
        if (!yion.transfer(to, amount)) revert TokenTransferFailed();
    }

    function _paymentToken() internal view override returns (address) {
        return address(yion);
    }
}
