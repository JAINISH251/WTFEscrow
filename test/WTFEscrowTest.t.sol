// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/WTFEscrow.sol";
import "../src/FeeVault.sol";
import "../src/WTFReputation.sol";

contract WTFEscrowTest is Test {
    WTFEscrow escrow;
    FeeVault feeVault;
    WTFReputation reputation;

    address buyer;
    address seller;
    address arbitrator;
    address thirdParty;

    uint256 constant ESCROW_AMOUNT = 1 ether;
    uint256 constant FEE = 0.025 ether;
    uint256 constant SELLER_AMOUNT = 0.975 ether;

    function setUp() public {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        arbitrator = makeAddr("arbitrator");
        thirdParty = makeAddr("thirdParty");

        vm.deal(buyer, 10 ether);
        vm.deal(seller, 10 ether);
        vm.deal(arbitrator, 10 ether);
        vm.deal(thirdParty, 10 ether);

        // Deploy FeeVault.
        feeVault = new FeeVault();

        // Deploy Reputation temporarily with zero escrow address.
        // The test contract is DEFAULT_ADMIN_ROLE.
        reputation = new WTFReputation(address(0));

        // Deploy Escrow with FeeVault + Reputation.
        escrow = new WTFEscrow(
            arbitrator,
            address(feeVault),
            address(reputation)
        );

        // Give the actual escrow contract permission
        // to update reputation.
        reputation.grantRole(
            reputation.REPORTER_ROLE(),
            address(escrow)
        );
    }

    // ---------------------------------------------------------
    // HELPER
    // ---------------------------------------------------------

    function createTestEscrow()
        internal
        returns (uint256 escrowId)
    {
        vm.prank(buyer);

        escrowId = escrow.createEscrow{
            value: ESCROW_AMOUNT
        }(payable(seller));
    }

    function acknowledgeTestDelivery(uint256 escrowId) internal {
        vm.prank(buyer);
        escrow.acknowledgeDelivery(escrowId);
    }

    // ---------------------------------------------------------
    // CREATE ESCROW
    // ---------------------------------------------------------

    function test_CreateEscrow() public {
        uint256 escrowId = createTestEscrow();

        (
            address escrowBuyer,
            address escrowSeller,
            uint256 amount,
            WTFEscrow.EscrowState state
        ) = escrow.escrows(escrowId);

        assertEq(escrowBuyer, buyer);
        assertEq(escrowSeller, seller);
        assertEq(amount, ESCROW_AMOUNT);

        assertEq(
            uint256(state),
            uint256(WTFEscrow.EscrowState.Active)
        );
    }

    // ---------------------------------------------------------
    // ACKNOWLEDGE DELIVERY
    // ---------------------------------------------------------

    function test_BuyerCanAcknowledgeDelivery() public {
        uint256 escrowId = createTestEscrow();

        vm.prank(buyer);

        escrow.acknowledgeDelivery(escrowId);

        assertGt(
            escrow.deliveryConfirmedAt(escrowId),
            0
        );
    }

    function test_NonBuyerCannotAcknowledgeDelivery() public {
        uint256 escrowId = createTestEscrow();

        vm.prank(seller);

        vm.expectRevert(
            WTFEscrow.NotPartyToEscrow.selector
        );

        escrow.acknowledgeDelivery(escrowId);
    }

    function test_CannotAcknowledgeDeliveryTwice() public {
        uint256 escrowId = createTestEscrow();

        acknowledgeTestDelivery(escrowId);

        vm.prank(buyer);

        vm.expectRevert(
            WTFEscrow.InvalidState.selector
        );

        escrow.acknowledgeDelivery(escrowId);
    }

    // ---------------------------------------------------------
    // RELEASE + FEE + REPUTATION
    // ---------------------------------------------------------

    function test_ReleaseAfter72Hours() public {
        uint256 escrowId = createTestEscrow();

        acknowledgeTestDelivery(escrowId);

        vm.warp(
            block.timestamp +
            escrow.DISPUTE_WINDOW() +
            1
        );

        uint256 sellerBalanceBefore = seller.balance;

        escrow.releaseAfterWindow(escrowId);

        uint256 sellerBalanceAfter = seller.balance;

        // Seller receives 97.5%.
        assertEq(
            sellerBalanceAfter,
            sellerBalanceBefore + SELLER_AMOUNT
        );

        // FeeVault receives 2.5%.
        assertEq(
            address(feeVault).balance,
            FEE
        );

        // Escrow amount becomes zero.
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

        // Successful trade updates reputation.
        assertEq(
            reputation.getScore(buyer),
            10
        );

        assertEq(
            reputation.getScore(seller),
            10
        );
    }

    function test_CannotReleaseBefore72Hours() public {
        uint256 escrowId = createTestEscrow();

        acknowledgeTestDelivery(escrowId);

        vm.prank(buyer);

        vm.expectRevert(
            WTFEscrow.DisputeWindowClosed.selector
        );

        escrow.releaseAfterWindow(escrowId);
    }

    function test_CannotReleaseWithoutAcknowledgement() public {
        uint256 escrowId = createTestEscrow();

        vm.expectRevert(
            WTFEscrow.InvalidState.selector
        );

        escrow.releaseAfterWindow(escrowId);
    }

    // ---------------------------------------------------------
    // CANCEL
    // ---------------------------------------------------------

    function test_SellerCanCancelEscrow() public {
        uint256 escrowId = createTestEscrow();

        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(seller);

        escrow.cancelEscrow(escrowId);

        uint256 buyerBalanceAfter = buyer.balance;

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

        assertEq(amount, 0);

        assertEq(
            uint256(state),
            uint256(WTFEscrow.EscrowState.Refunded)
        );
    }

    // ---------------------------------------------------------
    // DISPUTE
    // ---------------------------------------------------------

    function test_BuyerCanRaiseDispute() public {
        uint256 escrowId = createTestEscrow();

        vm.prank(buyer);

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

    function test_SellerCanRaiseDispute() public {
        uint256 escrowId = createTestEscrow();

        vm.prank(seller);

        escrow.raiseDispute(escrowId);

        assertTrue(
            escrow.disputeRaised(escrowId)
        );

        assertEq(
            escrow.disputeInitiator(escrowId),
            seller
        );
    }

    function test_ThirdPartyCannotRaiseDispute() public {
        uint256 escrowId = createTestEscrow();

        vm.prank(thirdParty);

        vm.expectRevert(
            WTFEscrow.NotPartyToEscrow.selector
        );

        escrow.raiseDispute(escrowId);
    }

    function test_CannotRaiseDisputeTwice() public {
        uint256 escrowId = createTestEscrow();

        vm.prank(buyer);

        escrow.raiseDispute(escrowId);

        vm.prank(buyer);

        vm.expectRevert(
            WTFEscrow.DisputeAlreadyRaised.selector
        );

        escrow.raiseDispute(escrowId);
    }

    function test_CannotRaiseDisputeAfter72Hours() public {
        uint256 escrowId = createTestEscrow();

        acknowledgeTestDelivery(escrowId);

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

    function test_CanRaiseDisputeWithin72Hours() public {
        uint256 escrowId = createTestEscrow();

        acknowledgeTestDelivery(escrowId);

        vm.warp(
            block.timestamp +
            70 hours
        );

        vm.prank(buyer);

        escrow.raiseDispute(escrowId);

        assertTrue(
            escrow.disputeRaised(escrowId)
        );

        assertEq(
            escrow.disputeInitiator(escrowId),
            buyer
        );
    }

    // ---------------------------------------------------------
    // DISPUTE RESOLUTION
    // ---------------------------------------------------------

    function test_ArbitratorResolvesDisputeToBuyer() public {
        uint256 escrowId = createTestEscrow();

        vm.prank(buyer);

        escrow.raiseDispute(escrowId);

        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(arbitrator);

        escrow.resolveDispute(
            escrowId,
            buyer
        );

        uint256 buyerBalanceAfter = buyer.balance;

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

        assertEq(amount, 0);

        assertEq(
            uint256(state),
            uint256(WTFEscrow.EscrowState.Resolved)
        );

        // Buyer won dispute:
        // initiator = buyer -> +5
        // respondent = seller -> -20
        assertEq(
            reputation.getScore(buyer),
            5
        );

        assertEq(
            reputation.getScore(seller),
            -20
        );
    }

    function test_ArbitratorResolvesDisputeToSeller() public {
        uint256 escrowId = createTestEscrow();

        vm.prank(buyer);

        escrow.raiseDispute(escrowId);

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(arbitrator);

        escrow.resolveDispute(
            escrowId,
            seller
        );

        uint256 sellerBalanceAfter = seller.balance;

        assertEq(
            sellerBalanceAfter,
            sellerBalanceBefore + ESCROW_AMOUNT
        );

        assertEq(
            reputation.getScore(buyer),
            -15
        );

        assertEq(
            reputation.getScore(seller),
            5
        );
    }

    function test_NonArbitratorCannotResolve() public {
        uint256 escrowId = createTestEscrow();

        vm.prank(buyer);

        escrow.raiseDispute(escrowId);

        vm.prank(buyer);

        vm.expectRevert(
            WTFEscrow.NotArbitrator.selector
        );

        escrow.resolveDispute(
            escrowId,
            buyer
        );
    }

    // ---------------------------------------------------------
    // INVALID DISPUTE RESOLUTION
    // ---------------------------------------------------------

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

    // ---------------------------------------------------------
    // REPUTATION INTEGRATION
    // ---------------------------------------------------------

    function test_ReputationReporterRoleGrantedToEscrow() public {
        assertTrue(
            reputation.hasRole(
                reputation.REPORTER_ROLE(),
                address(escrow)
            )
        );
    }
}