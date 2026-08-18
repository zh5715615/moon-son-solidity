// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../YION.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IMockTransferToken {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IMockYionPair {
    function sendToken(address token, address to, uint256 amount) external;
}

contract MockYionUsdt is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockYionUsdt6 is MockYionUsdt {
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract MockYionRouterQuote {
    address public pair;
    address public yion;
    address public usdt;
    uint256 public buyTokenQuote;
    uint256 public buyUsdtQuote;
    uint256 public sellUsdtQuote;

    function configure(address pairAddress, address yionAddress, address usdtAddress) external {
        pair = pairAddress;
        yion = yionAddress;
        usdt = usdtAddress;
    }

    function setQuotes(uint256 buyTokenOut, uint256 buyUsdtIn, uint256 sellUsdtOut) external {
        buyTokenQuote = buyTokenOut;
        buyUsdtQuote = buyUsdtIn;
        sellUsdtQuote = sellUsdtOut;
    }

    function getAmountsIn(uint256 amountOut, address[] calldata)
        external view returns (uint256[] memory amounts)
    {
        amounts = new uint256[](2);
        amounts[0] = buyUsdtQuote;
        amounts[1] = amountOut;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external view returns (uint256[] memory amounts)
    {
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = path[0] == usdt ? buyTokenQuote : sellUsdtQuote;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        uint256 amountOut = _swap(amountIn, amountOutMin, path, to);
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external {
        _swap(amountIn, amountOutMin, path, to);
    }

    function _swap(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) internal returns (uint256 amountOut) {
        amountOut = path[0] == usdt ? buyTokenQuote : sellUsdtQuote;
        require(amountOut >= amountOutMin, "mock insufficient output");
        require(
            IMockTransferToken(path[0]).transferFrom(msg.sender, pair, amountIn),
            "mock input failed"
        );
        IMockYionPair(pair).sendToken(path[1], to, amountOut);
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
