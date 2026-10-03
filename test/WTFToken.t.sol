//SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {WTFToken} from "../src/WTFToken.sol";

contract WTFTokenTest is Test {
    WTFToken public token;
    address public initialOwner;
    address public spender;
    address public receiver;

    function setUp() public {
        initialOwner = address(this);
        spender = makeAddr("spender");
        receiver = makeAddr("receiver");

        token = new WTFToken(initialOwner);
    }

    function testInitialSupply() public view {
        assertEq(token.balanceOf(initialOwner), 100_000_000 * 10 ** 18);

        assertEq(token.totalSupply(), 100_000_000 * 10 ** 18);
    }

    function testNameAndSymbol() public view {
        assertEq(token.name(), "WTF Token");
        assertEq(token.symbol(), "WTF");
    }

    function testDecimals() public view {
        assertEq(token.decimals(), 18);
    }

    function testTransfer() public {
        uint256 amount = 1_000 * 10 ** 18;

        // Prank as the initialOwner who holds the initial supply
        vm.prank(initialOwner);
        bool success = token.transfer(receiver, amount);

        assertTrue(success);
        assertEq(token.balanceOf(receiver), amount);
        assertEq(token.balanceOf(initialOwner), token.totalSupply() - amount);
    }

    function testApproveAndTransferFrom() public {
        address owner = initialOwner;
        uint256 amount = 500 * 10 ** 18;

        // 1. Owner approves spender to spend tokens
        vm.prank(owner);
        token.approve(spender, amount);

        assertEq(token.allowance(owner, spender), amount);

        // 2. Spender transfers tokens from owner to recipient
        vm.prank(spender);
        bool success = token.transferFrom(owner, receiver, amount);

        assertTrue(success);
        assertEq(token.balanceOf(receiver), amount);
        assertEq(token.balanceOf(owner), token.totalSupply() - amount);
        assertEq(token.allowance(owner, spender), 0); // Allowance should be consumed
    }

    function testOwnership() public view {
        assertEq(token.owner(), initialOwner);
    }
}
