interface IFeeVault {
    function computeFee(uint256 tradeAmount) external pure returns (uint256);

    function receiveFee(uint256 escrowId) external payable;
}