
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWTFReputation {

    // ---------------------------------------------------------
    // MILESTONE SUCCESS
    // ---------------------------------------------------------
    // milestoneScore:
    // 1 = Easy
    // 2 = Medium
    // 3 = Hard

    function recordSuccessfulTrade(
        address buyer,
        address seller,
        uint256 milestoneScore
    ) external;

    // ---------------------------------------------------------
    // DISPUTE OUTCOME
    // ---------------------------------------------------------

    function recordDisputeOutcome(
        address initiator,
        address respondent,
        address winner
    ) external;

    // ---------------------------------------------------------
    // VIEW
    // ---------------------------------------------------------

    function getScore(address user)
        external
        view
        returns (int256);

    function reputation(address user)
        external
        view
        returns (
            int256 score,
            uint256 totalTrades,
            uint256 disputesWon,
            uint256 disputesLost,
            uint256 lastUpdated
        );
}

