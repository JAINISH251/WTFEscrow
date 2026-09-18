
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract WTFEscrow {

    
    // 1. ESCROW STATES
    

    enum EscrowState {
        Active,
        Released,
        Refunded,
        Disputed,
        Resolved
    }

    
    // 2. ESCROW DATA
    

    struct Escrow {
        address payable buyer;
        address payable seller;
        uint256 amount;
        EscrowState state;
    }

    mapping(uint256 => Escrow) public escrows;

    uint256 public nextEscrowId;

    
    // 3. DISPUTE DATA
    

    uint256 public constant DISPUTE_WINDOW = 72 hours;

    address public arbitrator;

    mapping(uint256 => uint256) public deliveryConfirmedAt;

    mapping(uint256 => bool) public disputeRaised;

    mapping(uint256 => address) public disputeInitiator;

    
    // 4. EVENTS
    

    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed buyer,
        address indexed seller,
        uint256 amount
    );

    event EscrowReleased(
        uint256 indexed escrowId,
        uint256 amount
    );

    event EscrowRefunded(
        uint256 indexed escrowId,
        uint256 amount
    );

    event DisputeRaised(
        uint256 indexed escrowId,
        address indexed raisedBy,
        uint256 timestamp
    );

    event DisputeResolved(
        uint256 indexed escrowId,
        address indexed winner,
        uint256 amountReleased
    );

    
    // 5. CUSTOM ERRORS
    

    error NotPartyToEscrow();
    error DisputeWindowClosed();
    error DisputeAlreadyRaised();
    error NotArbitrator();
    error EscrowNotDisputed();

    // Existing contract errors
    error InvalidEscrow();
    error InvalidState();
    error IncorrectPayment();
    error TransferFailed();

    
    // 6. CONSTRUCTOR
    

    constructor(address _arbitrator) {
        arbitrator = _arbitrator;
    }

    
    // 7. CREATE ESCROW
    

    function createEscrow(
        address payable seller
    ) external payable returns (uint256 escrowId) {

        if (msg.value == 0) {
            revert IncorrectPayment();
        }

        escrowId = nextEscrowId++;

        escrows[escrowId] = Escrow({
            buyer: payable(msg.sender),
            seller: seller,
            amount: msg.value,
            state: EscrowState.Active
        });

        emit EscrowCreated(
            escrowId,
            msg.sender,
            seller,
            msg.value
        );
    }

    
    // 8. CONFIRM DELIVERY
    

    function confirmDelivery(
        uint256 escrowId
    ) external {

        Escrow storage e = escrows[escrowId];

        if (e.buyer == address(0)) {
            revert InvalidEscrow();
        }

        // Only buyer can confirm delivery.
        if (msg.sender != e.buyer) {
            revert NotPartyToEscrow();
        }

        if (e.state != EscrowState.Active) {
            revert InvalidState();
        }

        // Record when delivery was confirmed.
        deliveryConfirmedAt[escrowId] = block.timestamp;

        uint256 amount = e.amount;

        // Existing happy path:
        // Active -> Released
        e.state = EscrowState.Released;
        e.amount = 0;

        // Release funds to seller.
        (bool success, ) = e.seller.call{value: amount}("");

        if (!success) {
            revert TransferFailed();
        }

        emit EscrowReleased(
            escrowId,
            amount
        );
    }

    
    // 9. CANCEL ESCROW
    

    function cancelEscrow(
        uint256 escrowId
    ) external {

        Escrow storage e = escrows[escrowId];

        if (e.buyer == address(0)) {
            revert InvalidEscrow();
        }

        // Only seller can cancel.
        if (msg.sender != e.seller) {
            revert NotPartyToEscrow();
        }

        if (e.state != EscrowState.Active) {
            revert InvalidState();
        }

        uint256 amount = e.amount;

        e.state = EscrowState.Refunded;
        e.amount = 0;

        // Refund buyer.
        (bool success, ) = e.buyer.call{value: amount}("");

        if (!success) {
            revert TransferFailed();
        }

        emit EscrowRefunded(
            escrowId,
            amount
        );
    }

    
    // 10. RAISE DISPUTE
    

    function raiseDispute(
        uint256 escrowId
    ) external {

        Escrow storage e = escrows[escrowId];

        // Only buyer or seller can raise a dispute.
        if (
            msg.sender != e.buyer &&
            msg.sender != e.seller
        ) {
            revert NotPartyToEscrow();
        }

        // Disputes cannot be raised after the escrow
        // has been released, refunded, disputed, or resolved.
        if (
            e.state == EscrowState.Released ||
            e.state == EscrowState.Refunded ||
            e.state == EscrowState.Disputed ||
            e.state == EscrowState.Resolved
        ) {
            revert DisputeWindowClosed();
        }

        // If delivery has been confirmed,
        // enforce the 72-hour dispute window.
        if (deliveryConfirmedAt[escrowId] != 0) {

            if (
                block.timestamp >
                deliveryConfirmedAt[escrowId] + DISPUTE_WINDOW
            ) {
                revert DisputeWindowClosed();
            }
        }

        e.state = EscrowState.Disputed;

        disputeRaised[escrowId] = true;

        disputeInitiator[escrowId] = msg.sender;

        emit DisputeRaised(
            escrowId,
            msg.sender,
            block.timestamp
        );
    }

    
    // 11. RESOLVE DISPUTE
    

    function resolveDispute(
        uint256 escrowId,
        address winner
    ) external {

        // Only arbitrator can resolve disputes.
        if (msg.sender != arbitrator) {
            revert NotArbitrator();
        }

        Escrow storage e = escrows[escrowId];

        // Escrow must actually be disputed.
        if (e.state != EscrowState.Disputed) {
            revert EscrowNotDisputed();
        }

        // Winner must be buyer or seller.
        if (
            winner != e.buyer &&
            winner != e.seller
        ) {
            revert NotPartyToEscrow();
        }

        uint256 amount = e.amount;

        e.state = EscrowState.Resolved;
        e.amount = 0;

        // Send funds to the winning party.
        (bool success, ) = winner.call{value: amount}("");

        if (!success) {
            revert TransferFailed();
        }

        emit DisputeResolved(
            escrowId,
            winner,
            amount
        );
    }
}
