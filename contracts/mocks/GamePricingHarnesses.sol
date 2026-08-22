// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Landlords.sol";
import "../GoldenFlower.sol";
import "../Bullfigthing.sol";

/**
 * Deterministic 1:1 USDT/token quote harnesses for local tests. Production
 * contracts always use the chain-selected PancakeSwap V2 router.
 */
contract LandlordsPricingHarness is Landlords {
    uint256 public quoteBps = 10_000;

    constructor(address yionAddress, address dealerAddress, address rewardPoolAddress)
        Landlords(yionAddress, dealerAddress, rewardPoolAddress)
    {}

    function setQuoteBps(uint256 newQuoteBps) external {
        quoteBps = newQuoteBps;
    }

    function _quoteTokenAmount(uint256 usdtPriceCents) internal view override returns (uint256) {
        return usdtPriceCents * 1e16 * quoteBps / 10_000;
    }
}

contract GoldenFlowerPricingHarness is GoldenFlower {
    uint256 public quoteBps = 10_000;

    constructor(address yionAddress, address dealerAddress, address rewardPoolAddress)
        GoldenFlower(yionAddress, dealerAddress, rewardPoolAddress)
    {}

    function setQuoteBps(uint256 newQuoteBps) external {
        quoteBps = newQuoteBps;
    }

    function _quoteTokenAmount(uint256 usdtPriceCents) internal view override returns (uint256) {
        return usdtPriceCents * 1e16 * quoteBps / 10_000;
    }
}

contract BullfigthingPricingHarness is Bullfigthing {
    uint256 public quoteBps = 10_000;

    constructor(address beneficiary, address rewardPoolAddress, address yionAddress)
        Bullfigthing(beneficiary, rewardPoolAddress, yionAddress)
    {}

    function setQuoteBps(uint256 newQuoteBps) external {
        quoteBps = newQuoteBps;
    }

    function _quoteTokenAmount(uint256 usdtPriceCents) internal view override returns (uint256) {
        return usdtPriceCents * 1e16 * quoteBps / 10_000;
    }
}
