// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWTFReputation {


    function recordSuccessfulTrade(
        address buyer,
        address seller
    ) external;

    function recordDisputeOutcome(
        address initiator,
        address respondent,
        address winner
    ) external;

    function getScore(address user) external view returns (int256);

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