// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Interface

interface IFeeVault {
    function computeFee(uint256 tradeAmount) external pure returns (uint256);

    function receiveFee(uint256 escrowId) external payable;
}

contract WTFEscrow {
    // Imports

    IFeeVault public feeVault;

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

    event EscrowCreated(uint256 indexed escrowId, address indexed buyer, address indexed seller, uint256 amount);

    event EscrowReleased(uint256 indexed escrowId, uint256 amount);

    event EscrowRefunded(uint256 indexed escrowId, uint256 amount);

    event DisputeRaised(uint256 indexed escrowId, address indexed raisedBy, uint256 timestamp);

    event DisputeResolved(uint256 indexed escrowId, address indexed winner, uint256 amountReleased);

    event DeliveryAcknowledged(uint256 indexed escrowId, uint256 timestamp);

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

    constructor(address _arbitrator, address _feeVault) {
        arbitrator = _arbitrator;
        feeVault = IFeeVault(_feeVault);
    }

    // 7. CREATE ESCROW

    function createEscrow(address payable seller) external payable returns (uint256 escrowId) {
        if (msg.value == 0) {
            revert IncorrectPayment();
        }

        escrowId = nextEscrowId++;

        escrows[escrowId] =
            Escrow({buyer: payable(msg.sender), seller: seller, amount: msg.value, state: EscrowState.Active});

        emit EscrowCreated(escrowId, msg.sender, seller, msg.value);
    }

    // 8. Ack DELIVERY

    function acknowledgeDelivery(uint256 escrowId) external {
        Escrow storage e = escrows[escrowId];

        if (e.buyer == address(0)) {
            revert InvalidEscrow();
        }

        // Only buyer can acknowledge delivery.
        if (msg.sender != e.buyer) {
            revert NotPartyToEscrow();
        }

        if (e.state != EscrowState.Active) {
            revert InvalidState();
        }

        // Prevent delivery from being acknowledged twice.
        if (deliveryConfirmedAt[escrowId] != 0) {
            revert InvalidState();
        }

        // Start the 72-hour dispute window.
        deliveryConfirmedAt[escrowId] = block.timestamp;
        emit DeliveryAcknowledged(escrowId, block.timestamp);
    }

    //9.Actual Release

    function releaseAfterWindow(uint256 escrowId) external {
        Escrow storage e = escrows[escrowId];

        if (e.buyer == address(0)) {
            revert InvalidEscrow();
        }

        // Delivery must have been acknowledged first.
        if (deliveryConfirmedAt[escrowId] == 0) {
            revert InvalidState();
        }

        // 72 hours must have passed.
        if (block.timestamp < deliveryConfirmedAt[escrowId] + DISPUTE_WINDOW) {
            revert DisputeWindowClosed();
        }

        // Escrow must still be active.
        // If disputed, it cannot be released automatically.
        if (e.state != EscrowState.Active) {
            revert InvalidState();
        }

        uint256 amount = e.amount;

        uint256 fee = feeVault.computeFee(amount);
        uint256 sellerAmount = amount - fee;

        e.state = EscrowState.Released;
        e.amount = 0;

        // Send 2.5% fee to FeeVault
        feeVault.receiveFee{value: fee}(escrowId);

        // Send remaining 97.5% to seller
        (bool success,) = e.seller.call{value: sellerAmount}("");

        if (!success) {
            revert TransferFailed();
        }

        emit EscrowReleased(escrowId, sellerAmount);
    }

    // 10. CANCEL ESCROW

    function cancelEscrow(uint256 escrowId) external {
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
        (bool success,) = e.buyer.call{value: amount}("");

        if (!success) {
            revert TransferFailed();
        }

        emit EscrowRefunded(escrowId, amount);
    }

    // // 11. RAISE DISPUTE

    function raiseDispute(uint256 escrowId) external {
        Escrow storage e = escrows[escrowId];

        // DisputeAlreadyRaised error wire
        if (disputeRaised[escrowId]) {
            revert DisputeAlreadyRaised();
        }

        // Only buyer or seller can raise a dispute.
        if (msg.sender != e.buyer && msg.sender != e.seller) {
            revert NotPartyToEscrow();
        }

        // Disputes cannot be raised after the escrow
        // has been released, refunded, disputed, or resolved.
        if (
            e.state == EscrowState.Released || e.state == EscrowState.Refunded || e.state == EscrowState.Disputed
                || e.state == EscrowState.Resolved
        ) {
            revert DisputeWindowClosed();
        }

        // If delivery has been confirmed,
        // enforce the 72-hour dispute window.
        if (deliveryConfirmedAt[escrowId] != 0) {
            if (block.timestamp > deliveryConfirmedAt[escrowId] + DISPUTE_WINDOW) {
                revert DisputeWindowClosed();
            }
        }

        e.state = EscrowState.Disputed;

        disputeRaised[escrowId] = true;

        disputeInitiator[escrowId] = msg.sender;

        emit DisputeRaised(escrowId, msg.sender, block.timestamp);
    }

    // 12. RESOLVE DISPUTE

    function resolveDispute(uint256 escrowId, address winner) external {
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
        if (winner != e.buyer && winner != e.seller) {
            revert NotPartyToEscrow();
        }

        uint256 amount = e.amount;

        e.state = EscrowState.Resolved;
        e.amount = 0;

        // Send funds to the winning party.
        (bool success,) = winner.call{value: amount}("");

        if (!success) {
            revert TransferFailed();
        }

        emit DisputeResolved(escrowId, winner, amount);
    }
}
