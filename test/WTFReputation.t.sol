// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/WTFReputation.sol";

contract WTFReputationTest is Test {
    WTFReputation reputation;

    address escrow;
    address buyer;
    address seller;
    address attacker;

    function setUp() public {
        escrow = makeAddr("escrow");
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        attacker = makeAddr("attacker");

        reputation = new WTFReputation();

reputation.setReporter(escrow);
    }

    // 1. Successful trade
    function test_SuccessfulTradeScores() public {
        vm.prank(escrow);

        reputation.recordSuccessfulTrade(buyer, seller);

        assertEq(reputation.getScore(buyer), 10);

        assertEq(reputation.getScore(seller), 10);
    }

    // 2. Dispute winner scores
    function test_DisputeWinnerScores() public {
        vm.prank(escrow);

        reputation.recordDisputeOutcome(buyer, seller, buyer);

        assertEq(reputation.getScore(buyer), 5);

        assertEq(reputation.getScore(seller), -20);
    }

    // 3. Dispute loser scores
    function test_DisputeLoserScores() public {
        vm.prank(escrow);

        reputation.recordDisputeOutcome(buyer, seller, seller);

        assertEq(reputation.getScore(buyer), -15);

        assertEq(reputation.getScore(seller), 5);
    }

    // 4. Non-reporter cannot record
    function test_NonReporterCannotRecord() public {
        vm.prank(attacker);

        vm.expectRevert();

        reputation.recordSuccessfulTrade(buyer, seller);
    }

    // 5. Score can go negative
    function test_ScoreCanGoNegative() public {
        vm.startPrank(escrow);

        reputation.recordDisputeOutcome(buyer, seller, seller);

        reputation.recordDisputeOutcome(buyer, seller, seller);

        vm.stopPrank();

        assertEq(reputation.getScore(buyer), -30);
    }

    // 6. Escrow calls reputation
    function test_EscrowCallsReputation() public {
        vm.prank(escrow);

        reputation.recordDisputeOutcome(buyer, seller, buyer);

        assertEq(reputation.getScore(buyer), 5);

        assertEq(reputation.getScore(seller), -20);
    }



    function test_EscrowHasReporterRole() public {
    assertTrue(
        reputation.hasRole(
            reputation.REPORTER_ROLE(),
            escrow
        )
    );
}
}
