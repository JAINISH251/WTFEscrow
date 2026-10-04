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

        // Deploy contract
        reputation = new WTFReputation();

        // Admin configures authorized reporter
        reputation.setReporter(escrow);
    }

    // Helper to fetch score depending on public struct mapping
    function _getScore(address user) internal view returns (int256 score) {
        return score = reputation.getScore(user);
    }

    // 1. Successful Trade / Milestone Recording
    function test_SuccessfulTradeScores() public {
        uint256 milestoneScore = 2;

        vm.prank(escrow);
        reputation.recordSuccessfulTrade(buyer, seller, milestoneScore);

        assertEq(_getScore(buyer), 2);
        assertEq(_getScore(seller), 2);
    }

    // 2. Score Accumulation Across Multiple Trades
    function test_AccumulateReputation() public {
        vm.startPrank(escrow);
        reputation.recordSuccessfulTrade(buyer, seller, 1);
        reputation.recordSuccessfulTrade(buyer, seller, 3);
        vm.stopPrank();

        assertEq(_getScore(buyer), 4);
        assertEq(_getScore(seller), 4);
    }

    // 3. Revert when non-reporter tries to record a trade
    function test_RevertIf_UnauthorizedCaller() public {
        vm.prank(attacker);
        vm.expectRevert();
        reputation.recordSuccessfulTrade(buyer, seller, 2);
    }

    // 4. Revert when milestoneScore is out of valid bounds (1 to 3)
    function test_RevertIf_InvalidMilestoneScore() public {
        vm.startPrank(escrow);

        // Score 0 should revert
        vm.expectRevert(WTFReputation.InvalidMilestoneScore.selector);
        reputation.recordSuccessfulTrade(buyer, seller, 0);

        // Score 4 should revert
        vm.expectRevert(WTFReputation.InvalidMilestoneScore.selector);
        reputation.recordSuccessfulTrade(buyer, seller, 4);

        vm.stopPrank();
    }
}