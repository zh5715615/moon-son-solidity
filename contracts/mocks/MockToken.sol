// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Yi Yuan Test Token", "YYT") {
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
