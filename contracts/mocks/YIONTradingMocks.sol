// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../YION.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IMockTransferToken {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract MockYionUsdt is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockYionRouterQuote {
    uint256 public buyUsdtQuote;
    uint256 public sellUsdtQuote;

    function setQuotes(uint256 buyQuote, uint256 sellQuote) external {
        buyUsdtQuote = buyQuote;
        sellUsdtQuote = sellQuote;
    }

    function getAmountsIn(uint256 amountOut, address[] calldata)
        external view returns (uint256[] memory amounts)
    {
        amounts = new uint256[](2);
        amounts[0] = buyUsdtQuote;
        amounts[1] = amountOut;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata)
        external view returns (uint256[] memory amounts)
    {
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = sellUsdtQuote;
    }
}

contract MockYionPair {
    address public immutable token0;
    address public immutable token1;

    constructor(address firstToken, address secondToken) {
        token0 = firstToken;
        token1 = secondToken;
    }

    function sendToken(address token, address to, uint256 amount) external {
        require(IMockTransferToken(token).transfer(to, amount), "mock transfer failed");
    }
}

contract YIONTradingHarness is YION {
    address private immutable testWhitelistAccount;

    constructor(address usdtAddress, address routerAddress, address whitelistAccount)
        YION(usdtAddress, routerAddress)
    {
        testWhitelistAccount = whitelistAccount;
    }

    function _isWhitelisted(address account) internal view override returns (bool) {
        return account == testWhitelistAccount || super._isWhitelisted(account);
    }
}
