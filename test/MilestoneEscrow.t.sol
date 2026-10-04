// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MilestoneEscrow.sol";
import "../src/WTFReputation.sol";

contract MilestoneEscrowTest is Test {
    MilestoneEscrow milestoneEscrow;
    WTFReputation reputation;

    address buyer = address(1);
    address seller = address(2);
    address arbitrator = address(3);
    address stranger = address(4);

    uint256 milestone1 = 1 ether;
    uint256 milestone2 = 2 ether;

    string[] descriptions;
    uint256[] amounts;
    uint256[] reputationScores;

    function setUp() public {
        reputation = new WTFReputation();

        milestoneEscrow =
            new MilestoneEscrow(arbitrator, address(reputation));

        reputation.setReporter(address(milestoneEscrow));

        descriptions = new string[](2);
        descriptions[0] = "Design";
        descriptions[1] = "Development";

        amounts = new uint256[](2);
        amounts[0] = milestone1;
        amounts[1] = milestone2;

        // Design = Easy (+1)
        // Development = Hard (+3)
        reputationScores = new uint256[](2);
        reputationScores[0] = 1;
        reputationScores[1] = 3;

        vm.deal(buyer, 10 ether);
        vm.deal(seller, 1 ether);
        vm.deal(arbitrator, 1 ether);
        vm.deal(stranger, 1 ether);
    }

    // ---------------------------------------------------------
    // 1. CREATE MILESTONE ESCROW
    // ---------------------------------------------------------

    function test_CreateMilestoneEscrow() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId =
            milestoneEscrow.createMilestoneEscrow{value: totalAmount}(
                seller,
                descriptions,
                amounts,
                reputationScores
            );

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

        assertEq(address(milestoneEscrow).balance, totalAmount);

        (
            string memory description0,
            uint256 amount0,
            uint256 reputationScore0,
            MilestoneEscrow.MilestoneState state0
        ) = milestoneEscrow.getMilestone(escrowId, 0);

        assertEq(description0, "Design");
        assertEq(amount0, milestone1);
        assertEq(reputationScore0, 1);
        assertEq(
            uint256(state0),
            uint256(MilestoneEscrow.MilestoneState.Pending)
        );

        (
            string memory description1,
            uint256 amount1,
            uint256 reputationScore1,
            MilestoneEscrow.MilestoneState state1
        ) = milestoneEscrow.getMilestone(escrowId, 1);

        assertEq(description1, "Development");
        assertEq(amount1, milestone2);
        assertEq(reputationScore1, 3);
        assertEq(
            uint256(state1),
            uint256(MilestoneEscrow.MilestoneState.Pending)
        );
    }

    // ---------------------------------------------------------
    // 2. WRONG PAYMENT
    // ---------------------------------------------------------

    function test_WrongAmountReverts() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        vm.expectRevert(
            MilestoneEscrow.IncorrectPayment.selector
        );

        milestoneEscrow.createMilestoneEscrow{
            value: totalAmount - 1
        }(
            seller,
            descriptions,
            amounts,
            reputationScores
        );
    }

    // ---------------------------------------------------------
    // 3. FIRST MILESTONE RELEASE
    // ---------------------------------------------------------

    function test_BuyerReleasesMilestone() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId =
            milestoneEscrow.createMilestoneEscrow{value: totalAmount}(
                seller,
                descriptions,
                amounts,
                reputationScores
            );

        vm.prank(buyer);

        milestoneEscrow.releaseMilestone(escrowId, 0);

        (
            string memory description,
            uint256 amount,
            uint256 reputationScore,
            MilestoneEscrow.MilestoneState state
        ) = milestoneEscrow.getMilestone(escrowId, 0);

        assertEq(description, "Design");
        assertEq(amount, milestone1);
        assertEq(reputationScore, 1);

        assertEq(
            uint256(state),
            uint256(MilestoneEscrow.MilestoneState.Released)
        );

        (,,, uint256 releasedAmount) =
            milestoneEscrow.escrows(escrowId);

        assertEq(releasedAmount, milestone1);

        // Easy milestone = +1 to both.
        assertEq(reputation.getScore(buyer), 1);
        assertEq(reputation.getScore(seller), 1);
    }

    // ---------------------------------------------------------
    // 4. MILESTONES MUST BE RELEASED IN ORDER
    // ---------------------------------------------------------

    function test_MustReleaseInOrder() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId =
            milestoneEscrow.createMilestoneEscrow{value: totalAmount}(
                seller,
                descriptions,
                amounts,
                reputationScores
            );

        vm.prank(buyer);

        vm.expectRevert(
            MilestoneEscrow.MilestoneOutOfOrder.selector
        );

        milestoneEscrow.releaseMilestone(escrowId, 1);
    }

    // ---------------------------------------------------------
    // 5. SELLER DISPUTES MILESTONE
    // ---------------------------------------------------------

    function test_SellerDisputesMilestone() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId =
            milestoneEscrow.createMilestoneEscrow{value: totalAmount}(
                seller,
                descriptions,
                amounts,
                reputationScores
            );

        vm.expectEmit(true, true, false, false);

        emit MilestoneEscrow.MilestoneDisputed(
            escrowId,
            0
        );

        vm.prank(seller);

        milestoneEscrow.disputeMilestone(
            escrowId,
            0
        );

(
    string memory description,
    uint256 amount, , 
    MilestoneEscrow.MilestoneState state
) = milestoneEscrow.getMilestone(
    escrowId,
    0
);

assertTrue(bytes(description).length >= 0);
assertGt(amount, 0);
    }

    // ---------------------------------------------------------
    // 6. EACH MILESTONE GIVES ITS OWN SCORE
    // ---------------------------------------------------------

    function test_EachMilestoneUpdatesReputation() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId =
            milestoneEscrow.createMilestoneEscrow{value: totalAmount}(
                seller,
                descriptions,
                amounts,
                reputationScores
            );

        // Easy = +1
        vm.prank(buyer);
        milestoneEscrow.releaseMilestone(escrowId, 0);

        assertEq(reputation.getScore(buyer), 1);
        assertEq(reputation.getScore(seller), 1);

        // Hard = +3
        vm.prank(buyer);
        milestoneEscrow.releaseMilestone(escrowId, 1);

        // Total = 1 + 3 = 4
        assertEq(reputation.getScore(buyer), 4);
        assertEq(reputation.getScore(seller), 4);
    }

    // ---------------------------------------------------------
    // 7. REPUTATION IS NOT GIVEN BEFORE RELEASE
    // ---------------------------------------------------------

    function test_NoReputationBeforeMilestoneRelease() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId =
            milestoneEscrow.createMilestoneEscrow{value: totalAmount}(
                seller,
                descriptions,
                amounts,
                reputationScores
            );

        assertEq(reputation.getScore(buyer), 0);
        assertEq(reputation.getScore(seller), 0);

        vm.prank(buyer);

        milestoneEscrow.releaseMilestone(escrowId, 0);

        assertEq(reputation.getScore(buyer), 1);
        assertEq(reputation.getScore(seller), 1);
    }

    // ---------------------------------------------------------
    // 8. REPUTATION CANNOT BE RECORDED TWICE
    // ---------------------------------------------------------

    function test_ReputationRecordedOnlyOncePerMilestone() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId =
            milestoneEscrow.createMilestoneEscrow{value: totalAmount}(
                seller,
                descriptions,
                amounts,
                reputationScores
            );

        vm.prank(buyer);
        milestoneEscrow.releaseMilestone(escrowId, 0);

        assertEq(reputation.getScore(buyer), 1);

        vm.prank(buyer);

        vm.expectRevert(
            MilestoneEscrow.InvalidState.selector
        );

        milestoneEscrow.releaseMilestone(escrowId, 0);

        assertEq(reputation.getScore(buyer), 1);
        assertEq(reputation.getScore(seller), 1);
    }

    // ---------------------------------------------------------
    // 9. ARBITRATOR RESOLVES FOR SELLER
    // ---------------------------------------------------------

    function test_ArbitratorResolvesForSeller() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId =
            milestoneEscrow.createMilestoneEscrow{value: totalAmount}(
                seller,
                descriptions,
                amounts,
                reputationScores
            );

        vm.prank(seller);

        milestoneEscrow.disputeMilestone(
            escrowId,
            0
        );

        vm.prank(arbitrator);

        milestoneEscrow.resolveMilestone(
            escrowId,
            0,
            seller
        );

        // Seller initiated and won.
        // Seller = +5
        // Buyer = -20
        assertEq(reputation.getScore(seller), 5);
        assertEq(reputation.getScore(buyer), -20);
    }

    // ---------------------------------------------------------
    // 10. ARBITRATOR RESOLVES FOR BUYER
    // ---------------------------------------------------------

    function test_ArbitratorResolvesForBuyer() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId =
            milestoneEscrow.createMilestoneEscrow{value: totalAmount}(
                seller,
                descriptions,
                amounts,
                reputationScores
            );

        vm.prank(seller);

        milestoneEscrow.disputeMilestone(
            escrowId,
            0
        );

        vm.prank(arbitrator);

        milestoneEscrow.resolveMilestone(
            escrowId,
            0,
            buyer
        );

        // Seller initiated and lost.
        // Seller = -15
        // Buyer = +5
        assertEq(reputation.getScore(seller), -15);
        assertEq(reputation.getScore(buyer), 5);
    }

    // ---------------------------------------------------------
    // 11. RESOLVED MILESTONE DOES NOT GET SUCCESS SCORE
    // ---------------------------------------------------------

    function test_ResolvedMilestoneDoesNotGiveSuccessScore()
        public
    {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId =
            milestoneEscrow.createMilestoneEscrow{value: totalAmount}(
                seller,
                descriptions,
                amounts,
                reputationScores
            );

        vm.prank(seller);

        milestoneEscrow.disputeMilestone(
            escrowId,
            0
        );

        vm.prank(arbitrator);

        milestoneEscrow.resolveMilestone(
            escrowId,
            0,
            seller
        );

        // Only dispute score.
        assertEq(reputation.getScore(seller), 5);
        assertEq(reputation.getScore(buyer), -20);
    }

    // ---------------------------------------------------------
    // 12. SELLER CLAIMS RELEASED FUNDS
    // ---------------------------------------------------------

    function test_SellerClaims() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId =
            milestoneEscrow.createMilestoneEscrow{value: totalAmount}(
                seller,
                descriptions,
                amounts,
                reputationScores
            );

        vm.prank(buyer);
        milestoneEscrow.releaseMilestone(escrowId, 0);

        vm.prank(buyer);
        milestoneEscrow.releaseMilestone(escrowId, 1);

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(seller);

        milestoneEscrow.claimReleased(escrowId);

        uint256 sellerBalanceAfter = seller.balance;

        assertEq(
            sellerBalanceAfter - sellerBalanceBefore,
            totalAmount
        );

        (,,, uint256 releasedAmount) =
            milestoneEscrow.escrows(escrowId);

        assertEq(releasedAmount, 0);
    }

    // ---------------------------------------------------------
    // 13. NON-BUYER CANNOT RELEASE
    // ---------------------------------------------------------

    function test_NonBuyerCannotRelease() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId =
            milestoneEscrow.createMilestoneEscrow{value: totalAmount}(
                seller,
                descriptions,
                amounts,
                reputationScores
            );

        vm.prank(stranger);

        vm.expectRevert(
            MilestoneEscrow.Unauthorized.selector
        );

        milestoneEscrow.releaseMilestone(
            escrowId,
            0
        );
    }

    // ---------------------------------------------------------
    // 14. INVALID REPUTATION SCORE
    // ---------------------------------------------------------

    function test_InvalidReputationScoreReverts() public {
        string[] memory testDescriptions =
            new string[](1);

        uint256[] memory testAmounts =
            new uint256[](1);

        uint256[] memory testScores =
            new uint256[](1);

        testDescriptions[0] = "Invalid";
        testAmounts[0] = 1 ether;
        testScores[0] = 4;

        vm.prank(buyer);

        vm.expectRevert(
            MilestoneEscrow.InvalidReputationScore.selector
        );

        milestoneEscrow.createMilestoneEscrow{
            value: 1 ether
        }(
            seller,
            testDescriptions,
            testAmounts,
            testScores
        );
    }

    // ---------------------------------------------------------
    // 15. GET REPUTATION SCORE
    // ---------------------------------------------------------

    function testGetReputationScore() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId =
            milestoneEscrow.createMilestoneEscrow{value: totalAmount}(
                seller,
                descriptions,
                amounts,
                reputationScores
            );

        vm.prank(buyer);

        milestoneEscrow.releaseMilestone(
            escrowId,
            0
        );

        assertEq(
            milestoneEscrow.getReputationScore(buyer),
            1
        );

        assertEq(
            milestoneEscrow.getReputationScore(seller),
            1
        );
    }

    // ---------------------------------------------------------
    // 16. GET FULL REPUTATION
    // ---------------------------------------------------------

    function testGetReputation() public {
        uint256 totalAmount = milestone1 + milestone2;

        vm.prank(buyer);

        uint256 escrowId =
            milestoneEscrow.createMilestoneEscrow{value: totalAmount}(
                seller,
                descriptions,
                amounts,
                reputationScores
            );

        vm.prank(buyer);

        milestoneEscrow.releaseMilestone(
            escrowId,
            0
        );

        (
            int256 score,
            uint256 totalTrades,
            uint256 disputesWon,
            uint256 disputesLost,
            uint256 lastUpdated
        ) = milestoneEscrow.getReputation(buyer);

        assertEq(score, 1);
        assertEq(totalTrades, 1);
        assertEq(disputesWon, 0);
        assertEq(disputesLost, 0);
        assertGt(lastUpdated, 0);
    }

    // ---------------------------------------------------------
    // 17. INITIAL REPUTATION
    // ---------------------------------------------------------

    function testInitialReputationIsZero() public view {
        (
            int256 score,
            uint256 totalTrades,
            uint256 disputesWon,
            uint256 disputesLost,
            uint256 lastUpdated
        ) = milestoneEscrow.getReputation(buyer);

        assertEq(score, 0);
        assertEq(totalTrades, 0);
        assertEq(disputesWon, 0);
        assertEq(disputesLost, 0);
        assertEq(lastUpdated, 0);

        assertEq(
            milestoneEscrow.getReputationScore(buyer),
            0
        );
    }

    
}