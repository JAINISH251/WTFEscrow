// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/WTFEscrow.sol";

contract Deploy is Script {

    function run() external returns (WTFEscrow escrow) {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        escrow = new WTFEscrow(vm.addr(deployerPrivateKey));

        vm.stopBroadcast();
    }
}