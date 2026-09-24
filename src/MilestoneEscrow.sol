// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MilestoneEscrow {

    // ---------------------------------------------------------
    // 1. MILESTONE STATE
    // ---------------------------------------------------------

    enum MilestoneState {
        Pending,
        Released,
        Disputed,
        Resolved
    }

    // ---------------------------------------------------------
    // 2. MILESTONE DATA
    // ---------------------------------------------------------

    struct Milestone {
        string description;
        uint256 amount;
        MilestoneState state;
    }

    // ---------------------------------------------------------
    // 3. ESCROW DATA
    // ---------------------------------------------------------

    struct MilestoneEscrowData {
        address buyer;
        address seller;
        Milestone[] milestones;
        uint256 totalAmount;
        uint256 releasedAmount;
    }

    mapping(uint256 => MilestoneEscrowData) public escrows;

    uint256 public nextEscrowId;

    // ---------------------------------------------------------
    // 4. ARBITRATOR
    // ---------------------------------------------------------

    address public arbitrator;

    // ---------------------------------------------------------
    // 5. EVENTS
    // ---------------------------------------------------------

    event MilestoneEscrowCreated(
        uint256 indexed escrowId,
        address indexed buyer,
        address indexed seller,
        uint256 totalAmount
    );

    event MilestoneReleased(
        uint256 indexed escrowId,
        uint256 indexed milestoneIndex,
        uint256 amount
    );

    event MilestoneDisputed(
        uint256 indexed escrowId,
        uint256 indexed milestoneIndex
    );

    event MilestoneResolved(
        uint256 indexed escrowId,
        uint256 indexed milestoneIndex,
        address indexed winner,
        uint256 amount
    );

    event ReleasedFundsClaimed(
        uint256 indexed escrowId,
        address indexed seller,
        uint256 amount
    );

    // ---------------------------------------------------------
    // 6. CUSTOM ERRORS
    // ---------------------------------------------------------

    error Unauthorized();
    error InvalidEscrow();
    error InvalidMilestone();
    error IncorrectPayment();
    error InvalidState();
    error MilestoneOutOfOrder();
    error NotArbitrator();
    error InvalidWinner();
    error TransferFailed();

    // ---------------------------------------------------------
    // 7. CONSTRUCTOR
    // ---------------------------------------------------------

    constructor(address _arbitrator) {
        arbitrator = _arbitrator;
    }

    // ---------------------------------------------------------
    // 8. CREATE MILESTONE ESCROW
    // ---------------------------------------------------------

    function createMilestoneEscrow(
        address seller,
        string[] calldata descriptions,
        uint256[] calldata amounts
    )
        external
        payable
        returns (uint256 escrowId)
    {
        if (descriptions.length == 0) {
            revert InvalidMilestone();
        }

        if (descriptions.length != amounts.length) {
            revert InvalidMilestone();
        }

        uint256 totalAmount;

        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        if (msg.value != totalAmount) {
            revert IncorrectPayment();
        }

        escrowId = nextEscrowId++;

        MilestoneEscrowData storage escrow = escrows[escrowId];

        escrow.buyer = msg.sender;
        escrow.seller = seller;
        escrow.totalAmount = totalAmount;

        for (uint256 i = 0; i < descriptions.length; i++) {
            escrow.milestones.push(
                Milestone({
                    description: descriptions[i],
                    amount: amounts[i],
                    state: MilestoneState.Pending
                })
            );
        }

        emit MilestoneEscrowCreated(
            escrowId,
            msg.sender,
            seller,
            totalAmount
        );
    }

    // ---------------------------------------------------------
    // 9. RELEASE MILESTONE
    // ---------------------------------------------------------

    function releaseMilestone(
        uint256 escrowId,
        uint256 milestoneIndex
    )
        external
    {
        MilestoneEscrowData storage escrow = escrows[escrowId];

        if (escrow.buyer == address(0)) {
            revert InvalidEscrow();
        }

        // Only buyer can release a milestone.
        if (msg.sender != escrow.buyer) {
            revert Unauthorized();
        }

        if (milestoneIndex >= escrow.milestones.length) {
            revert InvalidMilestone();
        }

        Milestone storage milestone =
            escrow.milestones[milestoneIndex];

        if (milestone.state != MilestoneState.Pending) {
            revert InvalidState();
        }

        // Milestones must be released in order.
        if (milestoneIndex > 0) {
            if (
                escrow.milestones[milestoneIndex - 1].state
                != MilestoneState.Released
            ) {
                revert MilestoneOutOfOrder();
            }
        }

        milestone.state = MilestoneState.Released;

        escrow.releasedAmount += milestone.amount;

        emit MilestoneReleased(
            escrowId,
            milestoneIndex,
            milestone.amount
        );
    }

    // ---------------------------------------------------------
    // 10. DISPUTE MILESTONE
    // ---------------------------------------------------------

    function disputeMilestone(
        uint256 escrowId,
        uint256 milestoneIndex
    )
        external
    {
        MilestoneEscrowData storage escrow = escrows[escrowId];

        if (escrow.buyer == address(0)) {
            revert InvalidEscrow();
        }

        // Only seller can dispute.
        if (msg.sender != escrow.seller) {
            revert Unauthorized();
        }

        if (milestoneIndex >= escrow.milestones.length) {
            revert InvalidMilestone();
        }

        Milestone storage milestone =
            escrow.milestones[milestoneIndex];

        if (milestone.state != MilestoneState.Pending) {
            revert InvalidState();
        }

        milestone.state = MilestoneState.Disputed;

        emit MilestoneDisputed(
            escrowId,
            milestoneIndex
        );
    }

    // ---------------------------------------------------------
    // 11. RESOLVE MILESTONE
    // ---------------------------------------------------------

    function resolveMilestone(
        uint256 escrowId,
        uint256 milestoneIndex,
        address winner
    )
        external
    {
        if (msg.sender != arbitrator) {
            revert NotArbitrator();
        }

        MilestoneEscrowData storage escrow = escrows[escrowId];

        if (escrow.buyer == address(0)) {
            revert InvalidEscrow();
        }

        if (milestoneIndex >= escrow.milestones.length) {
            revert InvalidMilestone();
        }

        if (
            winner != escrow.buyer &&
            winner != escrow.seller
        ) {
            revert InvalidWinner();
        }

        Milestone storage milestone =
            escrow.milestones[milestoneIndex];

        if (milestone.state != MilestoneState.Disputed) {
            revert InvalidState();
        }

        milestone.state = MilestoneState.Resolved;

        uint256 amount = milestone.amount;

        if (winner == escrow.seller) {
            escrow.releasedAmount += amount;
        }

        (bool success,) = winner.call{value: amount}("");

        if (!success) {
            revert TransferFailed();
        }

        emit MilestoneResolved(
            escrowId,
            milestoneIndex,
            winner,
            amount
        );
    }

    // ---------------------------------------------------------
    // 12. CLAIM RELEASED FUNDS
    // ---------------------------------------------------------

    function claimReleased(
        uint256 escrowId
    )
        external
    {
        MilestoneEscrowData storage escrow = escrows[escrowId];

        if (escrow.buyer == address(0)) {
            revert InvalidEscrow();
        }

        if (msg.sender != escrow.seller) {
            revert Unauthorized();
        }

        uint256 amount = escrow.releasedAmount;

        if (amount == 0) {
            revert InvalidState();
        }

        escrow.releasedAmount = 0;

        (bool success,) = escrow.seller.call{value: amount}("");

        if (!success) {
            revert TransferFailed();
        }

        emit ReleasedFundsClaimed(
            escrowId,
            escrow.seller,
            amount
        );
    }
   function getMilestone(
    uint256 escrowId,
    uint256 milestoneIndex
)
    external
    view
    returns (
        string memory description,
        uint256 amount,
        MilestoneState state
    )
{
    if (escrows[escrowId].buyer == address(0)) {
        revert InvalidEscrow();
    }

    if (milestoneIndex >= escrows[escrowId].milestones.length) {
        revert InvalidMilestone();
    }

    Milestone storage milestone = escrows[escrowId].milestones[milestoneIndex];

    return (
        milestone.description,
        milestone.amount,
        milestone.state
    );
}
}