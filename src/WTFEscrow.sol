// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Imports

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Interfaces
import {IFeeVault} from "./Interfaces/IFeeVault.sol";
import {IWTFReputation} from "./Interfaces/IWTFReputation.sol";

contract WTFEscrow is Ownable {
    // Interface address

    IFeeVault public feeVault;
    IWTFReputation public reputation;

    //External Contract address
    address public ondoTokenAddress;

    //  Internal Contract Address
    address public arbitrator;

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
        // ScoreBasedOnDifficulty
        uint256 difficultyScore;
    }

    mapping(uint256 => Escrow) public escrows;

    uint256 public nextEscrowId;

    // RWA DATA

    struct RWAPosition {
        address user;
        uint256 amount;
        address tokenAddress;
        bool open;
    }

    mapping(bytes32 => RWAPosition) public rwaPositions;

    // 3. DISPUTE DATA

    uint256 public constant DISPUTE_WINDOW = 72 hours;

    //   Mappings

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

    //RWA EVENT

    event RWAPositionOpened(address indexed user, uint256 amount, address tokenAddress, bytes32 positionId);

    event RWAPositionClosed(
        address indexed user, uint256 amount, address tokenAddress, bytes32 positionId, uint256 yield
    );

    // 5. CUSTOM ERRORS

    error NotPartyToEscrow();
    error DisputeWindowClosed();
    error DisputeAlreadyRaised();
    error NotArbitrator();
    error EscrowNotDisputed();

    // External Contract errors
    error InvalidTokenAddress();

    // Existing contract errors

    error InvalidEscrow();
    error InvalidAddress();
    error InvalidState();
    error IncorrectPayment();
    error TransferFailed();
    error AmountNotBeZero();
    error InvalidDifficultyScore();

    error RWAPositionNotFound();
    error NotRWAPositionOwner();

    // 6. CONSTRUCTOR

    constructor(address _arbitrator, address _feeVault, address _reputation) Ownable(msg.sender) {
        if (_arbitrator == address(0) || _feeVault == address(0) || _reputation == address(0)) {
            revert InvalidAddress();
        }
        arbitrator = _arbitrator;
        feeVault = IFeeVault(_feeVault);
        reputation = IWTFReputation(_reputation);
    }

    // Assign OndoToken address by owner only

    function setOndoTokenAddress(address _ondoTokenAddress) external onlyOwner {
        if (_ondoTokenAddress == address(0)) {
            revert InvalidTokenAddress();
        }

        ondoTokenAddress = _ondoTokenAddress;
    }

    // 7. CREATE ESCROW

    function createEscrow(address payable seller, uint256 difficultyScore) external payable returns (uint256 escrowId) {
        if (difficultyScore < 1 || difficultyScore > 3) {
        revert InvalidDifficultyScore(); // Declare this custom error at top of contract
    }
        
        if (msg.value == 0) {
            revert IncorrectPayment();
        }

        escrowId = nextEscrowId++;

        escrows[escrowId] =
            Escrow({buyer: payable(msg.sender), seller: seller, amount: msg.value, state: EscrowState.Active ,difficultyScore:difficultyScore });

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
        // slither-disable-next-line timestamp
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

        emit EscrowReleased(escrowId, sellerAmount);

        // Send 2.5% fee to FeeVault
        // slither-disable-next-line arbitrary-send-eth
        feeVault.receiveFee{value: fee}(escrowId);

        // Send remaining 97.5% to seller
        // slither-disable-next-line arbitrary-send-eth
        (bool success,) = e.seller.call{value: sellerAmount}("");

        if (!success) {
            revert TransferFailed();
        }

        reputation.recordSuccessfulTrade(e.buyer, e.seller, e.difficultyScore);
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

        emit EscrowRefunded(escrowId, amount);

        // Refund buyer.
        // slither-disable-next-line arbitrary-send-eth
        (bool success,) = e.buyer.call{value: amount}("");

        if (!success) {
            revert TransferFailed();
        }
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
            // slither-disable-next-line timestamp
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
        if (winner == address(0)) revert InvalidAddress();
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

        uint256 fee = feeVault.computeFee(amount);
        uint256 WinnerAmount = amount - fee;

        e.state = EscrowState.Resolved;
        e.amount = 0;

        address initiator = disputeInitiator[escrowId];

        address respondent = initiator == e.buyer ? e.seller : e.buyer;

        emit DisputeResolved(escrowId, winner, amount);

        // Send 2.5% fee to FeeVault
        feeVault.receiveFee{value: fee}(escrowId);

        // slither-disable-next-line arbitrary-send-eth
        (bool success,) = winner.call{value: WinnerAmount}("");

        if (!success) {
            revert TransferFailed();
        }

        reputation.recordDisputeOutcome(initiator, respondent, winner);
    }

    //  RWA POSITIONS FUNCTION

    function openRWAPosition(uint256 amount, bytes32 positionId) external {
        if (amount == 0) {
            revert AmountNotBeZero();
        }

        if (rwaPositions[positionId].user != address(0)) {
            revert InvalidState();
        }

        rwaPositions[positionId] =
            RWAPosition({user: msg.sender, amount: amount, tokenAddress: ondoTokenAddress, open: true});

        emit RWAPositionOpened(msg.sender, amount, ondoTokenAddress, positionId);
    }

    function closeRWAPosition(bytes32 positionId, uint256 yield) external {
        RWAPosition storage position = rwaPositions[positionId];

        // Position must exist and still be open.
        if (position.user == address(0) || !position.open) {
            revert RWAPositionNotFound();
        }

        // Only the user who opened the position can close it.
        if (msg.sender != position.user) {
            revert NotRWAPositionOwner();
        }

        uint256 amount = position.amount;
        address tokenAddress = position.tokenAddress;

        // Mark position as closed.
        position.open = false;

        emit RWAPositionClosed(msg.sender, amount, tokenAddress, positionId, yield);
    }
}

