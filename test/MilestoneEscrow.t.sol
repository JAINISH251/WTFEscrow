// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MilestoneEscrow.sol";

contract MilestoneEscrowTest is Test {
    MilestoneEscrow milestoneEscrow;

    address buyer = address(1);
    address seller = address(2);
    address arbitrator = address(3);
    address stranger = address(4);

    uint256 milestone1 = 1 ether;
    uint256 milestone2 = 2 ether;

    string[] descriptions;
    uint256[] amounts;

    function setUp() public {
        milestoneEscrow = new MilestoneEscrow(arbitrator);

        descriptions = new string[](2);
        descriptions[0] = "Design";
        descriptions[1] = "Development";

        amounts = new uint256[](2);
        amounts[0] = milestone1;
        amounts[1] = milestone2;

        vm.deal(buyer, 10 ether);
        vm.deal(seller, 1 ether);
        vm.deal(arbitrator, 1 ether);
        vm.deal(stranger, 1 ether);
    }

    // ---------------------------------------------------------
    // 1. test_CreateMilestoneEscrow
    // ---------------------------------------------------------

    function test_CreateMilestoneEscrow() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId = milestoneEscrow.createMilestoneEscrow{
            value: totalAmount
        }(seller, descriptions, amounts);

        assertEq(escrowId, 0);

        (
            address storedBuyer,
            address storedSeller,
            uint256 storedTotalAmount,
            uint256 releasedAmount
        ) = milestoneEscrow.escrows(escrowId);

        assertEq(storedBuyer, buyer);
        assertEq(storedSeller, seller);
        assertEq(storedTotalAmount, totalAmount);
        assertEq(releasedAmount, 0);

        // ETH should be locked inside the contract.
        assertEq(address(milestoneEscrow).balance, totalAmount);

        // Check first milestone.
        (
            string memory description0,
            uint256 amount0,
            MilestoneEscrow.MilestoneState state0
        ) = milestoneEscrow.getMilestone(escrowId, 0);

        assertEq(description0, "Design");
        assertEq(amount0, milestone1);
        assertEq(
            uint256(state0),
            uint256(MilestoneEscrow.MilestoneState.Pending)
        );

        // Check second milestone.
        (
            string memory description1,
            uint256 amount1,
            MilestoneEscrow.MilestoneState state1
        ) = milestoneEscrow.getMilestone(escrowId, 1);

        assertEq(description1, "Development");
        assertEq(amount1, milestone2);
        assertEq(
            uint256(state1),
            uint256(MilestoneEscrow.MilestoneState.Pending)
        );
    }

    // ---------------------------------------------------------
    // 2. test_WrongAmountReverts
    // ---------------------------------------------------------

    function test_WrongAmountReverts() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        vm.expectRevert(MilestoneEscrow.IncorrectPayment.selector);

        milestoneEscrow.createMilestoneEscrow{
            value: totalAmount - 1
        }(seller, descriptions, amounts);
    }

    // ---------------------------------------------------------
    // 3. test_BuyerReleasesMilestone
    // ---------------------------------------------------------

    function test_BuyerReleasesMilestone() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId = milestoneEscrow.createMilestoneEscrow{
            value: totalAmount
        }(seller, descriptions, amounts);

        vm.prank(buyer);

        milestoneEscrow.releaseMilestone(escrowId, 0);

        (
            string memory description,
            uint256 amount,
            MilestoneEscrow.MilestoneState state
        ) = milestoneEscrow.getMilestone(escrowId, 0);

        assertEq(description, "Design");
        assertEq(amount, milestone1);

        assertEq(
            uint256(state),
            uint256(MilestoneEscrow.MilestoneState.Released)
        );

        // releasedAmount should track released milestone funds.
        (
            ,
            ,
            ,
            uint256 releasedAmount
        ) = milestoneEscrow.escrows(escrowId);

        assertEq(releasedAmount, milestone1);
    }

    // ---------------------------------------------------------
    // 4. test_MustReleaseInOrder
    // ---------------------------------------------------------

    function test_MustReleaseInOrder() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId = milestoneEscrow.createMilestoneEscrow{
            value: totalAmount
        }(seller, descriptions, amounts);

        // Try to release milestone 1 before milestone 0.
        vm.prank(buyer);

        vm.expectRevert(MilestoneEscrow.MilestoneOutOfOrder.selector);

        milestoneEscrow.releaseMilestone(escrowId, 1);
    }

    // ---------------------------------------------------------
    // 5. test_SellerDisputesMilestone
    // ---------------------------------------------------------

    function test_SellerDisputesMilestone() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId = milestoneEscrow.createMilestoneEscrow{
            value: totalAmount
        }(seller, descriptions, amounts);

        vm.expectEmit(true, true, false, false);

        emit MilestoneEscrow.MilestoneDisputed(
            escrowId,
            0
        );

        vm.prank(seller);

        milestoneEscrow.disputeMilestone(escrowId, 0);

        (
            ,
            ,
            MilestoneEscrow.MilestoneState state
        ) = milestoneEscrow.getMilestone(escrowId, 0);

        assertEq(
            uint256(state),
            uint256(MilestoneEscrow.MilestoneState.Disputed)
        );
    }

    // ---------------------------------------------------------
    // 6. test_ArbitratorResolves
    // ---------------------------------------------------------

    function test_ArbitratorResolves() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId = milestoneEscrow.createMilestoneEscrow{
            value: totalAmount
        }(seller, descriptions, amounts);

        // Seller disputes milestone 0.
        vm.prank(seller);

        milestoneEscrow.disputeMilestone(escrowId, 0);

        uint256 sellerBalanceBefore = seller.balance;

        // Arbitrator resolves in favor of seller.
        vm.prank(arbitrator);

        milestoneEscrow.resolveMilestone(
            escrowId,
            0,
            seller
        );

        uint256 sellerBalanceAfter = seller.balance;

        assertEq(
            sellerBalanceAfter - sellerBalanceBefore,
            milestone1
        );

        (
            ,
            ,
            MilestoneEscrow.MilestoneState state
        ) = milestoneEscrow.getMilestone(escrowId, 0);

        assertEq(
            uint256(state),
            uint256(MilestoneEscrow.MilestoneState.Resolved)
        );
    }

    // ---------------------------------------------------------
    // 7. test_SellerClaims
    // ---------------------------------------------------------

    function test_SellerClaims() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId = milestoneEscrow.createMilestoneEscrow{
            value: totalAmount
        }(seller, descriptions, amounts);

        // Buyer releases milestone 0.
        vm.prank(buyer);

        milestoneEscrow.releaseMilestone(escrowId, 0);

        // Buyer releases milestone 1.
        vm.prank(buyer);

        milestoneEscrow.releaseMilestone(escrowId, 1);

        uint256 sellerBalanceBefore = seller.balance;

        // Seller claims all released funds.
        vm.prank(seller);

        milestoneEscrow.claimReleased(escrowId);

        uint256 sellerBalanceAfter = seller.balance;

        assertEq(
            sellerBalanceAfter - sellerBalanceBefore,
            totalAmount
        );

        // Released amount should now be zero.
        (
            ,
            ,
            ,
            uint256 releasedAmount
        ) = milestoneEscrow.escrows(escrowId);

        assertEq(releasedAmount, 0);
    }

    // ---------------------------------------------------------
    // 8. test_NonBuyerCannotRelease
    // ---------------------------------------------------------

    function test_NonBuyerCannotRelease() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId = milestoneEscrow.createMilestoneEscrow{
            value: totalAmount
        }(seller, descriptions, amounts);

        // Stranger tries to release milestone.
        vm.prank(stranger);

        vm.expectRevert(MilestoneEscrow.Unauthorized.selector);

        milestoneEscrow.releaseMilestone(escrowId, 0);
    }
}