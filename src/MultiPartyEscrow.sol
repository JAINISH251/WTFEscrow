// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MultiPartyEscrow {
    // ---------------------------------------------------------
    // 1. STATE
    // ---------------------------------------------------------

    enum MultiEscrowState {
        Funding,
        Active,
        Released,
        Disputed,
        Resolved
    }

    // ---------------------------------------------------------
    // 2. PARTY SHARE
    // ---------------------------------------------------------

    struct PartyShare {
        address party;
        uint256 shareBPS;
    }

    // ---------------------------------------------------------
    // 3. ESCROW DATA
    // ---------------------------------------------------------

    struct MultiEscrow {
        PartyShare[] buyers;
        PartyShare[] sellers;

        uint256 totalAmount;
        uint256 amountFunded;

        MultiEscrowState state;
    }

    mapping(uint256 => MultiEscrow) public escrows;

    uint256 public nextEscrowId;

    // Tracks whether a buyer has funded.
    mapping(uint256 => mapping(address => bool)) public hasFunded;

    // ---------------------------------------------------------
    // 4. DELIVERY / DISPUTE DATA
    // ---------------------------------------------------------

    uint256 public constant DISPUTE_WINDOW = 72 hours;

    mapping(uint256 => uint256) public deliveryConfirmedAt;

    mapping(uint256 => bool) public disputeRaised;

    address public arbitrator;

    // ---------------------------------------------------------
    // 5. EVENTS
    // ---------------------------------------------------------

    event MultiEscrowCreated(
        uint256 indexed escrowId,
        address indexed creator
    );

    event ShareFunded(
        uint256 indexed escrowId,
        address indexed buyer,
        uint256 amount
    );

    event DeliveryAcknowledged(
        uint256 indexed escrowId,
        address indexed buyer,
        uint256 timestamp
    );

    event DisputeRaised(
        uint256 indexed escrowId,
        address indexed raisedBy
    );

    event DisputeResolved(
        uint256 indexed escrowId,
        bool buyersWin
    );

    event SellerPaid(
        uint256 indexed escrowId,
        address indexed seller,
        uint256 amount
    );

    event BuyerRefunded(
        uint256 indexed escrowId,
        address indexed buyer,
        uint256 amount
    );

    // ---------------------------------------------------------
    // 6. CUSTOM ERRORS
    // ---------------------------------------------------------

    error InvalidEscrow();
    error InvalidShares();
    error InvalidParty();
    error NotBuyer();
    error NotSeller();
    error AlreadyFunded();
    error IncorrectFundingAmount();
    error FundingNotComplete();
    error InvalidState();
    error DisputeWindowClosed();
    error AlreadyDisputed();
    error NotPartyToEscrow();
    error NotArbitrator();
    error TransferFailed();

    // ---------------------------------------------------------
    // 7. CONSTRUCTOR
    // ---------------------------------------------------------

    constructor(address _arbitrator) {
        arbitrator = _arbitrator;
    }

    // ---------------------------------------------------------
    // 8. CREATE MULTI ESCROW
    // ---------------------------------------------------------

    function createMultiEscrow(
        PartyShare[] calldata buyers,
        PartyShare[] calldata sellers
    )
        external
        returns (uint256 escrowId)
    {
        if (buyers.length == 0 || sellers.length == 0) {
            revert InvalidShares();
        }

        uint256 buyerTotal;
        uint256 sellerTotal;

        // Validate buyer shares.
        for (uint256 i = 0; i < buyers.length; i++) {
            if (buyers[i].party == address(0)) {
                revert InvalidParty();
            }

            buyerTotal += buyers[i].shareBPS;
        }

        // Validate seller shares.
        for (uint256 i = 0; i < sellers.length; i++) {
            if (sellers[i].party == address(0)) {
                revert InvalidParty();
            }

            sellerTotal += sellers[i].shareBPS;
        }

        if (buyerTotal != 10000 || sellerTotal != 10000) {
            revert InvalidShares();
        }

        escrowId = nextEscrowId++;

        MultiEscrow storage escrow = escrows[escrowId];

        for (uint256 i = 0; i < buyers.length; i++) {
            escrow.buyers.push(
                PartyShare({
                    party: buyers[i].party,
                    shareBPS: buyers[i].shareBPS
                })
            );
        }

        for (uint256 i = 0; i < sellers.length; i++) {
            escrow.sellers.push(
                PartyShare({
                    party: sellers[i].party,
                    shareBPS: sellers[i].shareBPS
                })
            );
        }

        escrow.state = MultiEscrowState.Funding;

        emit MultiEscrowCreated(
            escrowId,
            msg.sender
        );
    }

    // ---------------------------------------------------------
    // 9. FIND BUYER SHARE
    // ---------------------------------------------------------

    function _getBuyerShare(
        uint256 escrowId,
        address buyer
    )
        internal
        view
        returns (uint256)
    {
        MultiEscrow storage escrow = escrows[escrowId];

        for (uint256 i = 0; i < escrow.buyers.length; i++) {
            if (escrow.buyers[i].party == buyer) {
                return escrow.buyers[i].shareBPS;
            }
        }

        revert NotBuyer();
    }

    // ---------------------------------------------------------
    // 10. CHECK BUYER
    // ---------------------------------------------------------

    function _isBuyer(
        uint256 escrowId,
        address buyer
    )
        internal
        view
        returns (bool)
    {
        MultiEscrow storage escrow = escrows[escrowId];

        for (uint256 i = 0; i < escrow.buyers.length; i++) {
            if (escrow.buyers[i].party == buyer) {
                return true;
            }
        }

        return false;
    }

    // ---------------------------------------------------------
    // 11. CHECK SELLER
    // ---------------------------------------------------------

    function _isSeller(
        uint256 escrowId,
        address seller
    )
        internal
        view
        returns (bool)
    {
        MultiEscrow storage escrow = escrows[escrowId];

        for (uint256 i = 0; i < escrow.sellers.length; i++) {
            if (escrow.sellers[i].party == seller) {
                return true;
            }
        }

        return false;
    }

    // ---------------------------------------------------------
    // 12. FUND SHARE
    // ---------------------------------------------------------

    function fundShare(
        uint256 escrowId
    )
        external
        payable
    {
        MultiEscrow storage escrow = escrows[escrowId];

        if (escrow.state != MultiEscrowState.Funding) {
            revert InvalidState();
        }

        if (!_isBuyer(escrowId, msg.sender)) {
            revert NotBuyer();
        }

        if (hasFunded[escrowId][msg.sender]) {
            revert AlreadyFunded();
        }

        uint256 shareBPS = _getBuyerShare(
            escrowId,
            msg.sender
        );

        // -----------------------------------------------------
        // First buyer establishes totalAmount.
        // -----------------------------------------------------

        if (escrow.totalAmount == 0) {
            if (msg.value == 0) {
                revert IncorrectFundingAmount();
            }

            escrow.totalAmount =
                (msg.value * 10000) / shareBPS;

            // Make sure the calculation was exact.
            if (
                escrow.totalAmount * shareBPS
                != msg.value * 10000
            ) {
                revert IncorrectFundingAmount();
            }
        }

        uint256 expectedAmount =
            (escrow.totalAmount * shareBPS) / 10000;

        if (msg.value != expectedAmount) {
            revert IncorrectFundingAmount();
        }

        hasFunded[escrowId][msg.sender] = true;

        escrow.amountFunded += msg.value;

        emit ShareFunded(
            escrowId,
            msg.sender,
            msg.value
        );

        // -----------------------------------------------------
        // Automatically become Active when fully funded.
        // -----------------------------------------------------

        if (escrow.amountFunded == escrow.totalAmount) {
            escrow.state = MultiEscrowState.Active;
        }
    }

    // ---------------------------------------------------------
    // 13. ACKNOWLEDGE DELIVERY
    // ---------------------------------------------------------

    function acknowledgeDelivery(
        uint256 escrowId
    )
        external
    {
        MultiEscrow storage escrow = escrows[escrowId];

        if (escrow.state != MultiEscrowState.Active) {
            revert InvalidState();
        }

        if (!_isBuyer(escrowId, msg.sender)) {
            revert NotBuyer();
        }

        if (deliveryConfirmedAt[escrowId] != 0) {
            revert InvalidState();
        }

        deliveryConfirmedAt[escrowId] = block.timestamp;

        emit DeliveryAcknowledged(
            escrowId,
            msg.sender,
            block.timestamp
        );
    }

    // ---------------------------------------------------------
    // 14. RAISE DISPUTE
    // ---------------------------------------------------------

    function raiseDispute(
        uint256 escrowId
    )
        external
    {
        MultiEscrow storage escrow = escrows[escrowId];

        if (
            !_isBuyer(escrowId, msg.sender)
            && !_isSeller(escrowId, msg.sender)
        ) {
            revert NotPartyToEscrow();
        }

        if (
            escrow.state != MultiEscrowState.Active
        ) {
            revert InvalidState();
        }

        if (disputeRaised[escrowId]) {
            revert AlreadyDisputed();
        }

        // If delivery has been acknowledged,
        // enforce the 72-hour window.
        if (deliveryConfirmedAt[escrowId] != 0) {
            if (
                block.timestamp >
                deliveryConfirmedAt[escrowId]
                + DISPUTE_WINDOW
            ) {
                revert DisputeWindowClosed();
            }
        }

        disputeRaised[escrowId] = true;

        escrow.state = MultiEscrowState.Disputed;

        emit DisputeRaised(
            escrowId,
            msg.sender
        );
    }

    // ---------------------------------------------------------
    // 15. RESOLVE DISPUTE
    // ---------------------------------------------------------

    function resolveDispute(
        uint256 escrowId,
        bool buyersWin
    )
        external
    {
        if (msg.sender != arbitrator) {
            revert NotArbitrator();
        }

        MultiEscrow storage escrow = escrows[escrowId];

        if (
            escrow.state != MultiEscrowState.Disputed
        ) {
            revert InvalidState();
        }

        escrow.state = MultiEscrowState.Resolved;

        emit DisputeResolved(
            escrowId,
            buyersWin
        );

        if (buyersWin) {
            _refundBuyers(escrowId);
        } else {
            _paySellers(escrowId);
        }
    }

    // ---------------------------------------------------------
    // 16. REFUND BUYERS
    // ---------------------------------------------------------

    function _refundBuyers(
        uint256 escrowId
    )
        internal
    {
        MultiEscrow storage escrow = escrows[escrowId];

        for (uint256 i = 0; i < escrow.buyers.length; i++) {
            address buyer =
                escrow.buyers[i].party;

            uint256 amount =
                (escrow.totalAmount
                    * escrow.buyers[i].shareBPS)
                    / 10000;

            (bool success,) =
                payable(buyer).call{value: amount}("");

            if (!success) {
                revert TransferFailed();
            }

            emit BuyerRefunded(
                escrowId,
                buyer,
                amount
            );
        }
    }

    // ---------------------------------------------------------
    // 17. PAY SELLERS
    // ---------------------------------------------------------

    function _paySellers(
        uint256 escrowId
    )
        internal
    {
        MultiEscrow storage escrow = escrows[escrowId];

        for (uint256 i = 0; i < escrow.sellers.length; i++) {
            address seller =
                escrow.sellers[i].party;

            uint256 amount =
                (escrow.totalAmount
                    * escrow.sellers[i].shareBPS)
                    / 10000;

            (bool success,) =
                payable(seller).call{value: amount}("");

            if (!success) {
                revert TransferFailed();
            }

            emit SellerPaid(
                escrowId,
                seller,
                amount
            );
        }
    }

    // ---------------------------------------------------------
    // 18. RELEASE TO SELLERS
    // ---------------------------------------------------------

    function releaseToSellers(
        uint256 escrowId
    )
        external
    {
        MultiEscrow storage escrow = escrows[escrowId];

        if (escrow.state != MultiEscrowState.Active) {
            revert InvalidState();
        }

        if (deliveryConfirmedAt[escrowId] == 0) {
            revert InvalidState();
        }

        if (
            block.timestamp <
            deliveryConfirmedAt[escrowId]
            + DISPUTE_WINDOW
        ) {
            revert DisputeWindowClosed();
        }

        if (disputeRaised[escrowId]) {
            revert InvalidState();
        }

        escrow.state = MultiEscrowState.Released;

        _paySellers(escrowId);
    }
}