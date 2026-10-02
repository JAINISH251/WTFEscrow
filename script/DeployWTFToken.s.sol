
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/WTFToken.sol";

contract DeployWTFToken is Script {
    function run() external {
        vm.startBroadcast();

        WTFToken token = new WTFToken(msg.sender);

        vm.stopBroadcast();

        console.log("WTFToken deployed at:", address(token));
    }
}

