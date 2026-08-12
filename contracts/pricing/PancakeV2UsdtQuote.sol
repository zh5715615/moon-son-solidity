// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPancakeV2RouterQuote {
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

/**
 * @notice Converts a USDT price expressed in cents into the payment-token
 * amount quoted by the direct PancakeSwap V2 token/USDT pool.
 */
abstract contract PancakeV2UsdtQuote {
    error UnsupportedChain(uint256 chainId);
    error InvalidUsdtPrice();
    error InvalidPancakeQuote();

    uint256 public constant USDT_PRICE_SCALE = 100;
    uint256 private constant USDT_UNIT = 1e18;

    address private constant BSC_USDT = 0x55d398326f99059fF775485246999027B3197955;
    address private constant BSC_TESTNET_USDT = 0x5B32Cc7d18643073BDB15dAfafC5C35E736c91a5;
    address private constant BSC_V2_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address private constant BSC_TESTNET_V2_ROUTER = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1;

    function _paymentToken() internal view virtual returns (address);

    function usdtToken() public view returns (address) {
        if (block.chainid == 56) return BSC_USDT;
        if (block.chainid == 97) return BSC_TESTNET_USDT;
        revert UnsupportedChain(block.chainid);
    }

    function pancakeV2Router() public view returns (address) {
        if (block.chainid == 56) return BSC_V2_ROUTER;
        if (block.chainid == 97) return BSC_TESTNET_V2_ROUTER;
        revert UnsupportedChain(block.chainid);
    }

    /**
     * @param usdtPriceCents USDT price with two implied decimals; 3000 = 30.00 USDT.
     */
    function quoteTokenAmount(uint256 usdtPriceCents) public view returns (uint256) {
        return _quoteTokenAmount(usdtPriceCents);
    }

    function _quoteTokenAmount(uint256 usdtPriceCents) internal view virtual returns (uint256 tokenAmount) {
        if (usdtPriceCents == 0) revert InvalidUsdtPrice();

        address[] memory path = new address[](2);
        path[0] = _paymentToken();
        path[1] = usdtToken();

        uint256 usdtAmount = usdtPriceCents * USDT_UNIT / USDT_PRICE_SCALE;
        uint256[] memory amounts = IPancakeV2RouterQuote(pancakeV2Router()).getAmountsIn(usdtAmount, path);
        if (amounts.length != 2 || amounts[0] == 0) revert InvalidPancakeQuote();
        return amounts[0];
    }
}
