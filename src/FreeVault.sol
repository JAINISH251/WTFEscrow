// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FeeVault is Ownable, ReentrancyGuard {
    uint256 public constant FEE_BPS = 250;

    uint256 public totalFeesCollected;
    uint256 public totalFeesWithdrawn;

    event FeeReceived(address indexed from, uint256 amount, uint256 escrowId);

    event FeeWithdrawn(address indexed to, uint256 amount);

    error ZeroAmount();
    error InsufficientBalance();
    error TransferFailed();

    constructor() Ownable(msg.sender) {}

    function receiveFee(uint256 escrowId) external payable {
        if (msg.value == 0) {
            revert ZeroAmount();
        }

        totalFeesCollected += msg.value;

        emit FeeReceived(msg.sender, msg.value, escrowId);
    }

    function withdraw(address to, uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (amount > address(this).balance) {
            revert InsufficientBalance();
        }

        totalFeesWithdrawn += amount;

        (bool ok,) = to.call{value: amount}("");

        if (!ok) {
            revert TransferFailed();
        }

        emit FeeWithdrawn(to, amount);
    }

    function computeFee(uint256 tradeAmount) external pure returns (uint256) {
        return (tradeAmount * FEE_BPS) / 10000;
    }

    receive() external payable {
        totalFeesCollected += msg.value;
    }
}
