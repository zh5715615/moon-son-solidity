// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IYionPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IYionRouterQuote {
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external view returns (uint256[] memory amounts);
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external view returns (uint256[] memory amounts);
}

/**
 * @title YION
 * @notice Fixed-supply YION with a one-time 30-minute launch restriction.
 */
contract YION is ERC20 {
    error OnlyLauncher();
    error InvalidAddress();
    error InvalidPair();
    error TradingAlreadyActivated();
    error TradingNotActivated();
    error RestrictedTransfer();
    error NotWhitelisted();
    error TradeLimitExceeded();
    error DuplicateWhitelistAddress();

    uint256 public constant MAX_SUPPLY = 100_000_000 * 10 ** 8;
    uint256 public constant RESTRICTED_PERIOD = 30 minutes;
    uint256 public constant MAX_TRADE_USDT = 200 ether;
    uint256 public constant WHITELIST_SIZE = 100;

    address public immutable launcher;
    address public immutable usdt;
    IYionRouterQuote public immutable router;
    address public liquidityPair;
    uint256 public restrictedUntil;

    mapping(address => bool) public whitelist;

    event TradingActivated(address indexed pair, uint256 restrictedUntil);

    constructor(address usdtAddress, address routerAddress) ERC20("YION", "YION") {
        if (usdtAddress == address(0) || routerAddress == address(0)) revert InvalidAddress();
        launcher = msg.sender;
        usdt = usdtAddress;
        router = IYionRouterQuote(routerAddress);

        address[100] memory accounts = [
            address(0xD9F200aFF52895F1bdd221a883071E8BA94C30D0),
            address(0x7c7c066b6535318e6FE4D2c4DbfB0d23A488B41a),
            address(0x4464BC8898197f21C7eC3EdC5Bb0AE03799F3423),
            address(0x048F2BfCA2d75D1bC6DDB9340dd6629dB8A9119e),
            address(0x0b82F5Ca34dC0F08D24948984b3a96a2c9a89094),
            address(0xa27Ccb7c0CB1388077FaCCeFe20e02A733855a39),
            address(0xb900165211313E571E835F0004DBd8eE89369344),
            address(0xdD277869efD0057E5f59e99BB3494080e83bEAC5),
            address(0x212E31eA40336c07E4d09120207106a517f1814B),
            address(0x0981b5033441ee913969f6F463Ede45537155c7F),
            address(0xe5eCC8d9257A236D78f715Be5D1AbA0eDD9e54eE),
            address(0x7B67C9381C073137262598F7409ed4B33075c905),
            address(0x3B26A5C16A53d55D8E72287B258a75B251639e61),
            address(0xd2184C5015E4f031443B68076f9AD1B9C59387B5),
            address(0xa49330106D493E2ef9facaB96874298f35871b4b),
            address(0x25D9D5C4E0a8f9C5c7e93fF736E3Db11257F3e08),
            address(0xFDA1023E85eAB9966Dd531DC22CA990F2686Ee98),
            address(0x5239411EcD50801fBBc80cb3C9224F0e2d6dF916),
            address(0x212325E4ABe4B885E4Ac9238ad6d2935E52155c4),
            address(0x465887927398329530202c0FDE57eAAE383B906C),
            address(0x05282208bBceddB3Bf85505c52CD160C60de531b),
            address(0x7992cC8eCBBd424DBB76C58978fE823d9A8b0747),
            address(0x0E105E2DCc983336744E0b112c2C5aAC73AF900a),
            address(0xBC0A441E9bA2265E1685B03B9611c0f0D3845E07),
            address(0xB45521b08ddd775EC5EF25770a5b56C421A0d447),
            address(0xc2a2a79983897Ac75aeD731aA4757151a7a1d022),
            address(0x7045B585DcF7373888556c838061F1b9B38D64D2),
            address(0x233de28D254c92b049b0c1637f08689c2aac5df0),
            address(0xefDa12240Ce54c7aaf2C25674cBdAB6629241E0b),
            address(0x86AE0F86e9c6D2161B2e855d958c83049715B2e3),
            address(0x901D88d97b9d16b91F0E6f894Fee4c7789678a38),
            address(0x8873e6ccFa1A2DC9b0d7D29d58A6c3833d20601a),
            address(0x1AfaCC0c024D0AF0EE7398641ddE86017A7fBEC4),
            address(0x129309aA3b01BcBda75e996E40e006e8Cb038cEd),
            address(0x207BDA120864C4E5FE23Aa072FEa4cB63200dF18),
            address(0x82941B6a8657b51DAa623C7D604fAE8633Dd0b62),
            address(0x54ba15Ca86a9940bC60262665f8D4aca020d5D2D),
            address(0x2303301f112275fB5795e3d51c757a09f969B78b),
            address(0x15bD3729bf4D31aa2907D41E1C960be672762867),
            address(0x597E770e4de71E2a9dF967a032fe8efbB6696caD),
            address(0x4F42aEBd168e92dF50de2992c9e7323894bFAc24),
            address(0xAD232B7Ea1328316A858DCfce45d4ddF949c56a4),
            address(0x8FEe322ff76564a3D1E8E28BE8ECD799F50C18A7),
            address(0xf92675d741E38B7130fEf7Cc693a62b8a8477F7A),
            address(0xDBA9a0a411Ad93E10a75548501aeA6539fCF1654),
            address(0x3eE230D75C32F716193Cad3614F2f2d2A29D11E0),
            address(0x8255A1fC0Ec6AA7FBE0a0BC2e25864c843031A4E),
            address(0x41a08E2e11E2f76781E5D6abfF66484eb8C0333E),
            address(0x9A1327E199E67c1950666780DE95F8a2956EF21b),
            address(0x3d2B9727Df592A68c741a543c18bACD32C4056cA),
            address(0x67Bd8969c09B79E04996cE0a6D64AfD69530dd7c),
            address(0x2fd35AC226f20c18F7B17E2D6B24ef3F2878D572),
            address(0xCAAe35c5f9A929982675E9D192b71C7d9BAee904),
            address(0xD00d961A11c75D2f2b39BFb4d026166982a8A305),
            address(0x83CECf0E8918190b311c2f580D6be824E1223021),
            address(0xd1a746311701C6E929566AB5814D938ff4b66965),
            address(0x2BbF02a8921049F53C0bFEB14B82671e911Ac6D5),
            address(0x88153aDFf874458B4045beB9bb432FE775F7B3b2),
            address(0xb07E7450966Ff8815A19C925f53dFA1F636F34c8),
            address(0x01B3a0959Bf096A6777F6562b7018A36CDC2A557),
            address(0x4A4371e54e0a9579C3392edD1fd5b3FA05684C04),
            address(0x783b577f7f919b9aDc334704Ca52E3D92BE36883),
            address(0xE084e13EAB2A8De069482542fb380D8Da578408c),
            address(0x26373dFA93F923DF28dbaA67F67E060363635E2d),
            address(0x609C4FC63d80E1aE834D0b7203e9D53450Ad1075),
            address(0x67876cf7301e92A3213C2310D832b6157dE63a6b),
            address(0xb2F27821145D587D9b276C63d0b218001f53BA52),
            address(0xb0b92C766aE29a049e3880428b076B2795BE2c4d),
            address(0x3E3E8A359E3b1F673E4275e8e58f050a6BA7cB63),
            address(0x518156258BB4cc820135685CAEaF3694EEdF6b54),
            address(0x619AAd9e927E9F076BFB04Eee414713C516f661D),
            address(0x4630A92c3221a8Cd5b08C3DD677a0075E99E65d6),
            address(0x4Da73991B2238cdEEE99393EF91786ddb15E6F4F),
            address(0x84eE1db8e53fb61Bb1C841c1b43E20094dc7b2Cd),
            address(0x6569344370bB1906dBa9b6D103db81B2242ACFD9),
            address(0x6d8Ec57bDf6D3cC747d576c2281c45cF789E4bbc),
            address(0x36c4f492E9D2181C0B37dADb53e923ed48f6bAd8),
            address(0x87F4e0F3552DBE4505a2cEf17ed05424509d172c),
            address(0xE417333e1BCA03badF59cFA04423416a2180de4d),
            address(0xc0eBbD30b2073B3e998d6c2F5E2e81E47124Bc38),
            address(0xA78f74DE8fdb020aBD4b67123043753D70e6D44B),
            address(0x4e29D5717d26C21Eb87FbE77f617024153C1F122),
            address(0xb77a547F0011B1a2c067243640118DA84Eab2030),
            address(0x9B007BA4945370d461d2060d91d95A354EA3006C),
            address(0xdedAF9043646fD7C3d58bf45065B1640b00C49d7),
            address(0xeC8331382b60D5dDDb7720B6564787F744fDc380),
            address(0x0a2F15B5295f3f32368053c23924A0351176cf49),
            address(0x4424d5f03314783Eb711D138D85eC4fb36A0254d),
            address(0x489784391CB11b415ED99C01d0b5fcB7DD38f347),
            address(0xE662c5821115937cb3fb38452F75d2eBDA38F6C1),
            address(0x26838027A58abd354A9231ff622B8f7391803CD1),
            address(0x8F90977e35b8770eA6E3b6c5e42f37c04E45298a),
            address(0x4B10d378c0f5bf8CB4A5966de258E0373CE494B1),
            address(0x7cF552B16438D292D7A3b7486a9D8Fb60E952070),
            address(0xfCc978CDa833d202263a00448b59a3df64Fbb924),
            address(0x3C2f1Db447DB9cFC7A502Aaf05865c965597CE79),
            address(0x2EB2118607896E3Edd08421c00e04bA0906B5E22),
            address(0x55fFC264855B73e364f386fFD52A4e803BA57228),
            address(0x3e12331A7a54203479D774C35A67a6AE1338232b),
            address(0xFb5a610E6B06E52d5a3f2f7A23185Aa965cfE376)
        ];

        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == address(0)) revert InvalidAddress();
            if (whitelist[accounts[i]]) revert DuplicateWhitelistAddress();
            whitelist[accounts[i]] = true;
        }

        _mint(msg.sender, MAX_SUPPLY);
    }

    function decimals() public pure override returns (uint8) {
        return 8;
    }

    function activateTrading(address pair) external {
        if (msg.sender != launcher) revert OnlyLauncher();
        if (liquidityPair != address(0)) revert TradingAlreadyActivated();
        if (pair == address(0) || pair.code.length == 0) revert InvalidPair();
        address token0 = IYionPair(pair).token0();
        address token1 = IYionPair(pair).token1();
        if (!(
            (token0 == address(this) && token1 == usdt)
                || (token1 == address(this) && token0 == usdt)
        )) revert InvalidPair();

        liquidityPair = pair;
        restrictedUntil = block.timestamp + RESTRICTED_PERIOD;
        emit TradingActivated(pair, restrictedUntil);
    }

    function restrictionActive() public view returns (bool) {
        return liquidityPair != address(0) && block.timestamp < restrictedUntil;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            if (liquidityPair == address(0)) {
                if (from != launcher && to != launcher) revert TradingNotActivated();
            } else if (block.timestamp < restrictedUntil) {
                bool isBuy = from == liquidityPair;
                bool isSell = to == liquidityPair;
                if (!isBuy && !isSell) revert RestrictedTransfer();

                address trader = isBuy ? to : from;
                if (!_isWhitelisted(trader)) revert NotWhitelisted();
                if (_tradeUsdtValue(isBuy, value) >= MAX_TRADE_USDT) revert TradeLimitExceeded();
            }
        }
        super._update(from, to, value);
    }

    function _isWhitelisted(address account) internal view virtual returns (bool) {
        return whitelist[account];
    }

    function _tradeUsdtValue(bool isBuy, uint256 tokenAmount) internal view returns (uint256) {
        address[] memory path = new address[](2);
        uint256[] memory amounts;
        if (isBuy) {
            path[0] = usdt;
            path[1] = address(this);
            amounts = router.getAmountsIn(tokenAmount, path);
            return amounts[0];
        }

        path[0] = address(this);
        path[1] = usdt;
        amounts = router.getAmountsOut(tokenAmount, path);
        return amounts[1];
    }
}
