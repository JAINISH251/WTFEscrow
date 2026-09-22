// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FreeVault.sol";
import "../src/WTFEscrow.sol";

contract FeeVaultTest is Test {
    FeeVault vault;
    WTFEscrow escrow;

    address owner;
    address user;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");

        vm.prank(owner);
        vault = new FeeVault();
        escrow = new WTFEscrow(owner, address(vault));

        vm.deal(user, 10 ether);
    }

    // 1. Fee received updates balance and totalFeesCollected
    function test_ReceiveFeeUpdatesBalance() public {
        vm.prank(user);

        vm.expectEmit(true, false, false, true);

        emit FeeVault.FeeReceived(user, 1 ether, 1);

        vault.receiveFee{value: 1 ether}(1);

        assertEq(address(vault).balance, 1 ether);

        assertEq(vault.totalFeesCollected(), 1 ether);
    }

    // 2. Owner can withdraw fees
    function test_OwnerCanWithdraw() public {
        vm.prank(user);
        vault.receiveFee{value: 1 ether}(1);

        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(owner);

        vm.expectEmit(true, false, false, true);

        emit FeeVault.FeeWithdrawn(owner, 0.5 ether);

        vault.withdraw(owner, 0.5 ether);

        uint256 ownerBalanceAfter = owner.balance;

        assertEq(ownerBalanceAfter, ownerBalanceBefore + 0.5 ether);

        assertEq(address(vault).balance, 0.5 ether);

        assertEq(vault.totalFeesWithdrawn(), 0.5 ether);
    }

    // 3. Non-owner cannot withdraw
    function test_NonOwnerCannotWithdraw() public {
        vm.prank(user);
        vault.receiveFee{value: 1 ether}(1);

        vm.prank(user);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));

        vault.withdraw(user, 0.5 ether);
    }

    // 4. Cannot withdraw more than vault balance
    function test_WithdrawMoreThanBalance() public {
        vm.prank(user);
        vault.receiveFee{value: 1 ether}(1);

        vm.prank(owner);

        vm.expectRevert(FeeVault.InsufficientBalance.selector);

        vault.withdraw(owner, 2 ether);
    }

    // 5. Fee calculation is exactly 2.5%
    function test_ComputeFeeCorrect() public {
        uint256 fee = vault.computeFee(1 ether);

        assertEq(fee, 0.025 ether);
    }

    // 6. Escrow integration


    function test_EscrowIntegration() public {
    FeeVault feeVault = new FeeVault();

    WTFEscrow escrow = new WTFEscrow(
        owner,
        address(feeVault)
    );

    // Create 1 ETH escrow
    vm.deal(user, 1 ether);

    vm.prank(user);

    uint256 escrowId = escrow.createEscrow{
        value: 1 ether
    }(payable(owner));

    // Buyer acknowledges delivery
    vm.prank(user);

    escrow.acknowledgeDelivery(escrowId);

    // Move past 72-hour dispute window
    vm.warp(
        block.timestamp + escrow.DISPUTE_WINDOW() + 1
    );

    uint256 sellerBalanceBefore = owner.balance;
    uint256 feeVaultBalanceBefore = address(feeVault).balance;

    // Release escrow
    escrow.releaseAfterWindow(escrowId);

    uint256 sellerBalanceAfter = owner.balance;
    uint256 feeVaultBalanceAfter = address(feeVault).balance;

    // 2.5% fee = 0.025 ETH
    uint256 expectedFee = 0.025 ether;

    // Seller receives 97.5% = 0.975 ETH
    uint256 expectedSellerAmount = 0.975 ether;

    assertEq(
        feeVaultBalanceAfter - feeVaultBalanceBefore,
        expectedFee
    );

    assertEq(
        sellerBalanceAfter - sellerBalanceBefore,
        expectedSellerAmount
    );

    // Escrow should be released
    (
        ,
        ,
        uint256 amount,
        WTFEscrow.EscrowState state
    ) = escrow.escrows(escrowId);

    assertEq(amount, 0);

    assertEq(
        uint256(state),
        uint256(WTFEscrow.EscrowState.Released)
    );
}
}
