// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract WTFReputation is AccessControl {
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");

    struct ReputationData {
        int256 score;
        uint256 totalTrades;
        uint256 disputesWon;
        uint256 disputesLost;
        uint256 lastUpdated;
    }

    mapping(address => ReputationData) public reputation;

    int256 public constant TRADE_SUCCESS = 10;
    int256 public constant DISPUTE_WIN = 5;
    int256 public constant DISPUTE_LOSS = -15;
    int256 public constant BLAMED_WIN = 5;
    int256 public constant BLAMED_LOSS = -20;

    event ReputationUpdated(address indexed user, int256 delta, int256 newScore, string reason);

    error NotReporter();

    constructor() {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
}

function setReporter(address escrowAddress)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
{
    _grantRole(REPORTER_ROLE, escrowAddress);
}

    function recordSuccessfulTrade(address buyer, address seller) external onlyRole(REPORTER_ROLE) {
        _update(buyer, TRADE_SUCCESS, "successful_trade");

        _update(seller, TRADE_SUCCESS, "successful_trade");
    }

    function recordDisputeOutcome(address initiator, address respondent, address winner)
        external
        onlyRole(REPORTER_ROLE)
    {
        bool initiatorWon = (initiator == winner);

        _update(initiator, initiatorWon ? DISPUTE_WIN : DISPUTE_LOSS, initiatorWon ? "dispute_won" : "dispute_lost");

        _update(respondent, initiatorWon ? BLAMED_LOSS : BLAMED_WIN, initiatorWon ? "blamed_lost" : "blamed_won");


        initiatorWon ? reputation[initiator].disputesWon++ : reputation[initiator].disputesLost++;
        !initiatorWon ? reputation[respondent].disputesWon++ : reputation[respondent].disputesLost++;

    }

    function getScore(address user) external view returns (int256) {
        return reputation[user].score;
    }

    function _update(address user, int256 delta, string memory reason) internal {
        reputation[user].score += delta;
        reputation[user].totalTrades++;
        reputation[user].lastUpdated = block.timestamp;

        emit ReputationUpdated(user, delta, reputation[user].score, reason);
    }
}
