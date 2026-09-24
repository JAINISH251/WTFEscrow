// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FeeVault.sol";
import "../src/WTFEscrow.sol";
import "../src/WTFReputation.sol";

contract Vault is Test {
    FeeVault vault;

    WTFEscrow escrow;
    WTFReputation reputation;

    address owner;
    address buyer;
    address seller;
    address arbitrator;
    address recipient;
    address attacker;

    uint256 constant TRADE_AMOUNT = 1 ether;
    uint256 constant FEE = 0.025 ether;

    function setUp() public {
        owner = address(this);

        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        arbitrator = makeAddr("arbitrator");
        recipient = makeAddr("recipient");
        attacker = makeAddr("attacker");

        vm.deal(address(this), 10 ether);
        vm.deal(buyer, 10 ether);
        vm.deal(seller, 10 ether);
        vm.deal(arbitrator, 10 ether);
        vm.deal(attacker, 10 ether);

        vault = new FeeVault();

        // Reputation initially receives no escrow reporter.
        reputation = new WTFReputation(address(0));

        // Current WTFEscrow constructor requires 3 addresses.
        escrow = new WTFEscrow(
            arbitrator,
            address(vault),
            address(reputation)
        );

         vm.deal(address(escrow), 10 ether);

        // Allow WTFEscrow to update reputation.
        reputation.grantRole(
            reputation.REPORTER_ROLE(),
            address(escrow)
        );
    }

    // ---------------------------------------------------------
    // COMPUTE FEE
    // ---------------------------------------------------------

    function test_ComputeFee() public view {
        uint256 fee = vault.computeFee(
            TRADE_AMOUNT
        );

        assertEq(
            fee,
            FEE
        );
    }

    function test_ComputeFeeForZero() public view {
        assertEq(
            vault.computeFee(0),
            0
        );
    }

    // ---------------------------------------------------------
    // RECEIVE FEE
    // ---------------------------------------------------------

    function test_ReceiveFee() public {
        vm.prank(address(escrow));

        vault.receiveFee{
            value: FEE
        }(0);

        assertEq(
            address(vault).balance,
            FEE
        );

        assertEq(
            vault.totalFeesCollected(),
            FEE
        );
    }

    function test_ReceiveFeeCannotReceiveZero() public {
        vm.expectRevert(
            FeeVault.ZeroAmount.selector
        );

        vault.receiveFee(0);
    }

    // ---------------------------------------------------------
    // DIRECT RECEIVE
    // ---------------------------------------------------------

    function test_DirectETHReceive() public {
        vm.deal(attacker, 1 ether);

        vm.prank(attacker);

        (bool success,) = address(vault).call{
            value: 0.1 ether
        }("");

        assertTrue(success);

        assertEq(
            address(vault).balance,
            0.1 ether
        );

        assertEq(
            vault.totalFeesCollected(),
            0.1 ether
        );
    }

    // ---------------------------------------------------------
    // WITHDRAW
    // ---------------------------------------------------------

    function test_OwnerCanWithdraw() public {
        vm.prank(address(escrow));

        vault.receiveFee{
            value: FEE
        }(0);

        uint256 recipientBalanceBefore =
            recipient.balance;

        vault.withdraw(
            recipient,
            FEE
        );

        uint256 recipientBalanceAfter =
            recipient.balance;

        assertEq(
            recipientBalanceAfter,
            recipientBalanceBefore + FEE
        );

        assertEq(
            vault.totalFeesWithdrawn(),
            FEE
        );

        assertEq(
            address(vault).balance,
            0
        );
    }

    function test_NonOwnerCannotWithdraw() public {
        vm.prank(address(escrow));

        vault.receiveFee{
            value: FEE
        }(0);

        vm.prank(attacker);

        vm.expectRevert();

        vault.withdraw(
            recipient,
            FEE
        );
    }

    function test_CannotWithdrawZero() public {
        vm.expectRevert(
            FeeVault.ZeroAmount.selector
        );

        vault.withdraw(
            recipient,
            0
        );
    }

    function test_CannotWithdrawMoreThanBalance() public {
        vm.prank(address(escrow));

        vault.receiveFee{
            value: FEE
        }(0);

        vm.expectRevert(
            FeeVault.InsufficientBalance.selector
        );

        vault.withdraw(
            recipient,
            FEE + 1
        );
    }

    // ---------------------------------------------------------
    // ESCROW + FEEVAULT INTEGRATION
    // ---------------------------------------------------------

    function test_EscrowSendsFeeToVault() public {
        vm.prank(buyer);

        uint256 escrowId =
            escrow.createEscrow{
                value: TRADE_AMOUNT
            }(payable(seller));

        vm.prank(buyer);

        escrow.acknowledgeDelivery(
            escrowId
        );

        vm.warp(
            block.timestamp +
            escrow.DISPUTE_WINDOW() +
            1
        );

        escrow.releaseAfterWindow(
            escrowId
        );

        assertEq(
            address(vault).balance,
            FEE
        );

        assertEq(
            vault.totalFeesCollected(),
            FEE
        );
    }
}