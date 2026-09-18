
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/WTFEscrow.sol";

contract WTFEscrowTest is Test {

    WTFEscrow escrow;

    address buyer;
    address seller;
    address arbitrator;
    address thirdParty;

    uint256 constant ESCROW_AMOUNT = 1 ether;

    
    // SETUP
    

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        arbitrator = makeAddr("arbitrator");
        thirdParty = makeAddr("thirdParty");

        escrow = new WTFEscrow(arbitrator);

        vm.deal(buyer, 10 ether);
        vm.deal(seller, 10 ether);
        vm.deal(arbitrator, 10 ether);
        vm.deal(thirdParty, 10 ether);
    }

    
    // HELPER: CREATE ESCROW
    

    function createTestEscrow()
        internal
        returns (uint256 escrowId)
    {
        vm.prank(buyer);

        escrowId = escrow.createEscrow{
            value: ESCROW_AMOUNT
        }(payable(seller));
    }

    
    // TEST 1
    // Buyer can raise dispute
    

    function test_BuyerCanRaiseDispute() public {
        uint256 escrowId = createTestEscrow();

        vm.prank(buyer);

        vm.expectEmit(true, true, false, true);

        emit WTFEscrow.DisputeRaised(
            escrowId,
            buyer,
            block.timestamp
        );

        escrow.raiseDispute(escrowId);

        (
            ,
            ,
            ,
            WTFEscrow.EscrowState state
        ) = escrow.escrows(escrowId);

        assertEq(
            uint256(state),
            uint256(WTFEscrow.EscrowState.Disputed)
        );

        assertTrue(
            escrow.disputeRaised(escrowId)
        );

        assertEq(
            escrow.disputeInitiator(escrowId),
            buyer
        );
    }

    
    // TEST 2
    // Seller can raise dispute
    

    function test_SellerCanRaiseDispute() public {
        uint256 escrowId = createTestEscrow();

        vm.prank(seller);

        vm.expectEmit(true, true, false, true);

        emit WTFEscrow.DisputeRaised(
            escrowId,
            seller,
            block.timestamp
        );

        escrow.raiseDispute(escrowId);

        (
            ,
            ,
            ,
            WTFEscrow.EscrowState state
        ) = escrow.escrows(escrowId);

        assertEq(
            uint256(state),
            uint256(WTFEscrow.EscrowState.Disputed)
        );

        assertTrue(
            escrow.disputeRaised(escrowId)
        );

        assertEq(
            escrow.disputeInitiator(escrowId),
            seller
        );
    }

    
    // TEST 3
    // Third party cannot raise dispute
    

    function test_ThirdPartyCannotRaiseDispute() public {
        uint256 escrowId = createTestEscrow();

        vm.prank(thirdParty);

        vm.expectRevert(
            WTFEscrow.NotPartyToEscrow.selector
        );

        escrow.raiseDispute(escrowId);
    }

    
    // TEST 4
    // Dispute window closed after delivery confirmation
    

    function test_DisputeWindowExpiredReverts() public {
        uint256 escrowId = createTestEscrow();

        // Buyer confirms delivery.
        // According to the contract, this immediately
        // releases the escrow.
        vm.prank(buyer);

        escrow.confirmDelivery(escrowId);

        // Move beyond the 72-hour window.
        vm.warp(
            block.timestamp +
            escrow.DISPUTE_WINDOW() +
            1
        );

        vm.prank(buyer);

        vm.expectRevert(
            WTFEscrow.DisputeWindowClosed.selector
        );

        escrow.raiseDispute(escrowId);
    }

    
    // TEST 5
    // Arbitrator resolves dispute to buyer
    

    function test_ArbitratorResolvesToBuyer() public {
        uint256 escrowId = createTestEscrow();

        // Buyer raises dispute.
        vm.prank(buyer);

        escrow.raiseDispute(escrowId);

        uint256 buyerBalanceBefore = buyer.balance;

        // Arbitrator resolves in favor of buyer.
        vm.prank(arbitrator);

        vm.expectEmit(true, true, false, true);

        emit WTFEscrow.DisputeResolved(
            escrowId,
            buyer,
            ESCROW_AMOUNT
        );

        escrow.resolveDispute(
            escrowId,
            buyer
        );

        uint256 buyerBalanceAfter = buyer.balance;

        // Buyer receives escrow amount.
        assertEq(
            buyerBalanceAfter,
            buyerBalanceBefore + ESCROW_AMOUNT
        );

        (
            ,
            ,
            uint256 amount,
            WTFEscrow.EscrowState state
        ) = escrow.escrows(escrowId);

        // Escrow amount should be zero.
        assertEq(amount, 0);

        // State should be Resolved.
        assertEq(
            uint256(state),
            uint256(WTFEscrow.EscrowState.Resolved)
        );
    }

    
    // TEST 6
    // Non-arbitrator cannot resolve dispute
    

    function test_NonArbitratorCannotResolve() public {
        uint256 escrowId = createTestEscrow();

        // Buyer raises dispute.
        vm.prank(buyer);

        escrow.raiseDispute(escrowId);

        // Buyer tries to resolve.
        vm.prank(buyer);

        vm.expectRevert(
            WTFEscrow.NotArbitrator.selector
        );

        escrow.resolveDispute(
            escrowId,
            buyer
        );
    }

    
    // BONUS TEST 1
    // Cannot raise dispute twice
    

    function test_CannotRaiseDisputeTwice() public {
        uint256 escrowId = createTestEscrow();

        // First dispute.
        vm.prank(buyer);

        escrow.raiseDispute(escrowId);

        // Second dispute should fail.
        vm.prank(buyer);

        vm.expectRevert(
            WTFEscrow.DisputeWindowClosed.selector
        );

        escrow.raiseDispute(escrowId);
    }

    
    // BONUS TEST 2
    // Arbitrator resolves dispute to seller
    

    function test_ArbitratorResolvesToSeller() public {
        uint256 escrowId = createTestEscrow();

        // Buyer raises dispute.
        vm.prank(buyer);

        escrow.raiseDispute(escrowId);

        uint256 sellerBalanceBefore = seller.balance;

        // Arbitrator resolves in favor of seller.
        vm.prank(arbitrator);

        escrow.resolveDispute(
            escrowId,
            seller
        );

        uint256 sellerBalanceAfter = seller.balance;

        // Seller receives escrow amount.
        assertEq(
            sellerBalanceAfter,
            sellerBalanceBefore + ESCROW_AMOUNT
        );

        (
            ,
            ,
            uint256 amount,
            WTFEscrow.EscrowState state
        ) = escrow.escrows(escrowId);

        // Escrow amount should be zero.
        assertEq(amount, 0);

        // State should be Resolved.
        assertEq(
            uint256(state),
            uint256(WTFEscrow.EscrowState.Resolved)
        );
    }

    
    // BONUS TEST 3
    // Cannot resolve non-disputed escrow
    

    function test_CannotResolveNonDisputedEscrow() public {
        uint256 escrowId = createTestEscrow();

        vm.prank(arbitrator);

        vm.expectRevert(
            WTFEscrow.EscrowNotDisputed.selector
        );

        escrow.resolveDispute(
            escrowId,
            buyer
        );
    }
}

