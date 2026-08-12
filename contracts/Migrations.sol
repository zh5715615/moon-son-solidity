// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Migrations {
    address public owner = msg.sender;
    uint256 public lastCompletedMigration;

    modifier restricted() {
        require(msg.sender == owner, "Migrations: restricted");
        _;
    }

    function setCompleted(uint256 completed) external restricted {
        lastCompletedMigration = completed;
    }
}
