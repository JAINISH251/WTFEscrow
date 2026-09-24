
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MultiPartyEscrow} from "../src/MultiPartyEscrow.sol";

contract MultiPartyEscrowTest is Test {
    MultiPartyEscrow public multiEscrow;

    address public arbitrator = address(100);

    address public buyer1 = address(1);
    address public buyer2 = address(2);

    address public seller1 = address(3);
    address public seller2 = address(4);

    address public nonParty = address(99);

    uint256 public constant TOTAL_AMOUNT = 10 ether;

    function setUp() public {
        multiEscrow = new MultiPartyEscrow(arbitrator);

        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);

        vm.deal(seller1, 1 ether);
        vm.deal(seller2, 1 ether);

        vm.deal(nonParty, 10 ether);
        vm.deal(arbitrator, 10 ether);
    }

    // ---------------------------------------------------------
    // HELPERS
    // ---------------------------------------------------------

    function _createEscrow() internal returns (uint256 escrowId) {
        MultiPartyEscrow.PartyShare[] memory buyers =
            new MultiPartyEscrow.PartyShare[](2);

        buyers[0] = MultiPartyEscrow.PartyShare({
            party: buyer1,
            shareBPS: 6000
        });

        buyers[1] = MultiPartyEscrow.PartyShare({
            party: buyer2,
            shareBPS: 4000
        });

        MultiPartyEscrow.PartyShare[] memory sellers =
            new MultiPartyEscrow.PartyShare[](2);

        sellers[0] = MultiPartyEscrow.PartyShare({
            party: seller1,
            shareBPS: 7000
        });

        sellers[1] = MultiPartyEscrow.PartyShare({
            party: seller2,
            shareBPS: 3000
        });

        escrowId = multiEscrow.createMultiEscrow(
            buyers,
            sellers
        );
    }

    function _fundEscrow(uint256 escrowId) internal {
        // Buyer 1 owns 60%.
        vm.prank(buyer1);
        multiEscrow.fundShare{value: 6 ether}(escrowId);

        // Buyer 2 owns 40%.
        vm.prank(buyer2);
        multiEscrow.fundShare{value: 4 ether}(escrowId);
    }

    // ---------------------------------------------------------
    // 1. CREATE MULTI ESCROW
    // ---------------------------------------------------------

    function test_CreateMultiEscrow() public {
        uint256 escrowId = _createEscrow();

        (
            uint256 totalAmount,
            uint256 amountFunded,
            MultiPartyEscrow.MultiEscrowState state
        ) = multiEscrow.escrows(escrowId);

        assertEq(totalAmount, 0);
        assertEq(amountFunded, 0);

        assertEq(
            uint256(state),
            uint256(MultiPartyEscrow.MultiEscrowState.Funding)
        );

        assertEq(multiEscrow.nextEscrowId(), 1);
    }

    // ---------------------------------------------------------
    // 2. BUYER SHARES MUST SUM TO 10000
    // ---------------------------------------------------------

    function test_BuyerSharesMustSum10000() public {
        MultiPartyEscrow.PartyShare[] memory buyers =
            new MultiPartyEscrow.PartyShare[](2);

        buyers[0] = MultiPartyEscrow.PartyShare({
            party: buyer1,
            shareBPS: 6000
        });

        // 6000 + 3000 = 9000, not 10000.
        buyers[1] = MultiPartyEscrow.PartyShare({
            party: buyer2,
            shareBPS: 3000
        });

        MultiPartyEscrow.PartyShare[] memory sellers =
            new MultiPartyEscrow.PartyShare[](1);

        sellers[0] = MultiPartyEscrow.PartyShare({
            party: seller1,
            shareBPS: 10000
        });

        vm.expectRevert(
            MultiPartyEscrow.InvalidShares.selector
        );

        multiEscrow.createMultiEscrow(
            buyers,
            sellers
        );
    }

    // ---------------------------------------------------------
    // 3. FUNDING TRANSITIONS TO ACTIVE
    // ---------------------------------------------------------

    function test_FundingTransitionsToActive() public {
        uint256 escrowId = _createEscrow();

        // Initially Funding.
        (
            uint256 totalAmountBefore,
            uint256 amountFundedBefore,
            MultiPartyEscrow.MultiEscrowState stateBefore
        ) = multiEscrow.escrows(escrowId);

        assertEq(totalAmountBefore, 0);
        assertEq(amountFundedBefore, 0);

        assertEq(
            uint256(stateBefore),
            uint256(MultiPartyEscrow.MultiEscrowState.Funding)
        );

        // Buyer 1 funds 60%.
        vm.prank(buyer1);
        multiEscrow.fundShare{value: 6 ether}(escrowId);

        (
            uint256 totalAmountAfterFirst,
            uint256 amountFundedAfterFirst,
            MultiPartyEscrow.MultiEscrowState stateAfterFirst
        ) = multiEscrow.escrows(escrowId);

        assertEq(totalAmountAfterFirst, TOTAL_AMOUNT);
        assertEq(amountFundedAfterFirst, 6 ether);

        assertEq(
            uint256(stateAfterFirst),
            uint256(MultiPartyEscrow.MultiEscrowState.Funding)
        );

        // Buyer 2 funds remaining 40%.
        vm.prank(buyer2);
        multiEscrow.fundShare{value: 4 ether}(escrowId);

        (
            uint256 totalAmount,
            uint256 amountFunded,
            MultiPartyEscrow.MultiEscrowState state
        ) = multiEscrow.escrows(escrowId);

        assertEq(totalAmount, TOTAL_AMOUNT);
        assertEq(amountFunded, TOTAL_AMOUNT);

        assertEq(
            uint256(state),
            uint256(MultiPartyEscrow.MultiEscrowState.Active)
        );

        assertTrue(
            multiEscrow.hasFunded(escrowId, buyer1)
        );

        assertTrue(
            multiEscrow.hasFunded(escrowId, buyer2)
        );
    }

    // ---------------------------------------------------------
    // 4. WRONG FUND AMOUNT REVERTS
    // ---------------------------------------------------------

    function test_WrongFundAmountReverts() public {
        uint256 escrowId = _createEscrow();

        // Buyer 1 should pay 6 ETH.
        // Sends only 5 ETH.
        vm.prank(buyer1);

        vm.expectRevert(
            MultiPartyEscrow.IncorrectFundingAmount.selector
        );

        multiEscrow.fundShare{value: 5 ether}(escrowId);
    }

    // ---------------------------------------------------------
    // 5. RELEASE PROPORTIONAL TO SELLERS
    // ---------------------------------------------------------

    function test_ReleaseProportionalToSellers() public {
        uint256 escrowId = _createEscrow();

        _fundEscrow(escrowId);

        // Buyer acknowledges delivery.
        vm.prank(buyer1);
        multiEscrow.acknowledgeDelivery(escrowId);

        // Move forward 72 hours.
        vm.warp(
            block.timestamp
                + multiEscrow.DISPUTE_WINDOW()
        );

        uint256 seller1Before = seller1.balance;
        uint256 seller2Before = seller2.balance;

        multiEscrow.releaseToSellers(escrowId);

        // Seller 1 = 70%.
        uint256 expectedSeller1 =
            (TOTAL_AMOUNT * 7000) / 10000;

        // Seller 2 = 30%.
        uint256 expectedSeller2 =
            (TOTAL_AMOUNT * 3000) / 10000;

        assertEq(
            seller1.balance,
            seller1Before + expectedSeller1
        );

        assertEq(
            seller2.balance,
            seller2Before + expectedSeller2
        );

        (
            uint256 totalAmount,
            uint256 amountFunded,
            MultiPartyEscrow.MultiEscrowState state
        ) = multiEscrow.escrows(escrowId);

        assertEq(totalAmount, TOTAL_AMOUNT);
        assertEq(amountFunded, TOTAL_AMOUNT);

        assertEq(
            uint256(state),
            uint256(MultiPartyEscrow.MultiEscrowState.Released)
        );
    }

    // ---------------------------------------------------------
    // 6. DISPUTE BUYERS WIN
    // ---------------------------------------------------------

    function test_DisputeBuyersWin() public {
        uint256 escrowId = _createEscrow();

        _fundEscrow(escrowId);

        // Buyer raises dispute.
        vm.prank(buyer1);
        multiEscrow.raiseDispute(escrowId);

        (
            uint256 totalAmount,
            uint256 amountFunded,
            MultiPartyEscrow.MultiEscrowState state
        ) = multiEscrow.escrows(escrowId);

        assertEq(totalAmount, TOTAL_AMOUNT);
        assertEq(amountFunded, TOTAL_AMOUNT);

        assertEq(
            uint256(state),
            uint256(MultiPartyEscrow.MultiEscrowState.Disputed)
        );

        uint256 buyer1Before = buyer1.balance;
        uint256 buyer2Before = buyer2.balance;

        // Arbitrator decides buyers win.
        vm.prank(arbitrator);
        multiEscrow.resolveDispute(
            escrowId,
            true
        );

        uint256 expectedBuyer1 =
            (TOTAL_AMOUNT * 6000) / 10000;

        uint256 expectedBuyer2 =
            (TOTAL_AMOUNT * 4000) / 10000;

        assertEq(
            buyer1.balance,
            buyer1Before + expectedBuyer1
        );

        assertEq(
            buyer2.balance,
            buyer2Before + expectedBuyer2
        );

        (
            ,
            ,
            MultiPartyEscrow.MultiEscrowState finalState
        ) = multiEscrow.escrows(escrowId);

        assertEq(
            uint256(finalState),
            uint256(MultiPartyEscrow.MultiEscrowState.Resolved)
        );
    }

    // ---------------------------------------------------------
    // 7. DISPUTE SELLERS WIN
    // ---------------------------------------------------------

    function test_DisputeSellersWin() public {
        uint256 escrowId = _createEscrow();

        _fundEscrow(escrowId);

        // Seller raises dispute.
        vm.prank(seller1);
        multiEscrow.raiseDispute(escrowId);

        (
            ,
            ,
            MultiPartyEscrow.MultiEscrowState disputedState
        ) = multiEscrow.escrows(escrowId);

        assertEq(
            uint256(disputedState),
            uint256(MultiPartyEscrow.MultiEscrowState.Disputed)
        );

        uint256 seller1Before = seller1.balance;
        uint256 seller2Before = seller2.balance;

        // Arbitrator decides sellers win.
        vm.prank(arbitrator);
        multiEscrow.resolveDispute(
            escrowId,
            false
        );

        uint256 expectedSeller1 =
            (TOTAL_AMOUNT * 7000) / 10000;

        uint256 expectedSeller2 =
            (TOTAL_AMOUNT * 3000) / 10000;

        assertEq(
            seller1.balance,
            seller1Before + expectedSeller1
        );

        assertEq(
            seller2.balance,
            seller2Before + expectedSeller2
        );

        (
            ,
            ,
            MultiPartyEscrow.MultiEscrowState finalState
        ) = multiEscrow.escrows(escrowId);

        assertEq(
            uint256(finalState),
            uint256(MultiPartyEscrow.MultiEscrowState.Resolved)
        );
    }

    // ---------------------------------------------------------
    // 8. NON-PARTY CANNOT RAISE DISPUTE
    // ---------------------------------------------------------

    function test_NonPartyCannotRaiseDispute() public {
        uint256 escrowId = _createEscrow();

        _fundEscrow(escrowId);

        vm.prank(nonParty);

        vm.expectRevert(
            MultiPartyEscrow.NotPartyToEscrow.selector
        );

        multiEscrow.raiseDispute(escrowId);
    }
}
