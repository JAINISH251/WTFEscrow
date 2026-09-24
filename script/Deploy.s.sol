// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import "../src/FeeVault.sol";
import "../src/WTFReputation.sol";
import "../src/WTFEscrow.sol";
import "../src/MilestoneEscrow.sol";
import "../src/MultiPartyEscrow.sol";

contract Deploy is Script {
    function run()
        external
        returns (
            FeeVault feeVault,
            WTFReputation reputation,
            WTFEscrow escrow,
            MilestoneEscrow milestoneEscrow,
            MultiPartyEscrow multiPartyEscrow
        )
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy FeeVault
        feeVault = new FeeVault();

        // 2. Deploy WTFReputation
        reputation = new WTFReputation();

        // 3. Deploy main WTFEscrow
        escrow = new WTFEscrow(
            deployer,
            address(feeVault),
            address(reputation)
        );

        // 4. Authorize WTFEscrow as reputation reporter
        reputation.setReporter(address(escrow));

        // 5. Deploy MilestoneEscrow
        milestoneEscrow = new MilestoneEscrow(deployer);

        // 6. Deploy MultiPartyEscrow
        multiPartyEscrow = new MultiPartyEscrow(deployer);

        vm.stopBroadcast();
    }
}