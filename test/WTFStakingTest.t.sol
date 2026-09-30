// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";
import {WTFStaking} from "../src/WTFStaking.sol";

contract MockWTFToken is ERC20 {
    constructor() ERC20("WTF Token", "WTF") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract WTFStakingTest is Test {
    MockWTFToken public wtfToken;
    WTFStaking public staking;

    address public user = makeAddr("user");
    address public employer = makeAddr("employer");
    address public nonOwner = makeAddr("nonOwner");

    function setUp() public {
        wtfToken = new MockWTFToken();
        staking = new WTFStaking(address(wtfToken));

        wtfToken.mint(user, 1000 * 1e18);
    }

    function testStake() public {
        uint256 amount = 200 * 1e18;

        vm.startPrank(user);

        wtfToken.approve(address(staking), amount);

        vm.expectEmit(true, false, false, true);

        emit WTFStaking.UserStaked(user, amount, block.timestamp);

        staking.stake(amount);

        vm.stopPrank();

        (uint256 storedAmount, uint256 stakedAt, uint256 lastClaimedAt, bool active) = staking.userStakes(user);

        assertEq(storedAmount, amount);
        assertEq(stakedAt, lastClaimedAt);
        assertTrue(active);

        assertEq(staking.totalUserStaked(), amount);
        assertEq(wtfToken.balanceOf(address(staking)), amount);
    }

    function testStakeBelowMinimumReverts() public {
        uint256 amount = 99 * 1e18;

        vm.prank(user);

        vm.expectRevert(WTFStaking.StakeTooSmall.selector);
        staking.stake(amount);
    }

    function testStakeAlreadyActiveReverts() public {
        uint256 amount = 200 * 1e18;

        vm.startPrank(user);

        wtfToken.approve(address(staking), amount);

        staking.stake(amount);

        vm.expectRevert(WTFStaking.AlreadyStaking.selector);
        staking.stake(amount);

        vm.stopPrank();
    }

    function testClaimReward() public {
        uint256 stakeAmount = 1000 * 1e18;

        vm.startPrank(user);

        wtfToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);

        vm.stopPrank();

        // Fund the reward pool.
        wtfToken.mint(address(staking), 100 * 1e18);

        // Advance one year.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        uint256 expectedReward = 5 * 1e18;

        vm.startPrank(user);

        vm.expectEmit(true, false, false, true);
        emit WTFStaking.UserRewardClaimed(user, expectedReward, block.timestamp);

        staking.claimReward();

        vm.stopPrank();

        assertEq(
            wtfToken.balanceOf(user),
            5 * 1e18 + (0) // adjust if your initial balance differs
        );

        assertEq(staking.calculateReward(user), 0);
    }

    function testClaimRewardWithoutActiveStakeReverts() public {
        vm.prank(user);

        vm.expectRevert(WTFStaking.NoActiveStake.selector);
        staking.claimReward();
    }

    function testUnstake() public {
        uint256 stakeAmount = 1000 * 1e18;

        vm.startPrank(user);

        wtfToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);

        vm.stopPrank();

        // Fund reward pool.
        wtfToken.mint(address(staking), 100 * 1e18);

        // Create pending reward.
        vm.warp(block.timestamp + 365 days);

        uint256 balanceBefore = wtfToken.balanceOf(user);

        vm.prank(user);
        staking.unstake();

        uint256 expectedReward = 5 * 1e18;

        assertEq(wtfToken.balanceOf(user), balanceBefore + stakeAmount + expectedReward);

        (uint256 amount,,, bool active) = staking.userStakes(user);

        assertEq(amount, stakeAmount);
        assertFalse(active);

        assertEq(staking.totalUserStaked(), 0);
    }

    function testUnstakeWithoutActiveStakeReverts() public {
        vm.prank(user);

        vm.expectRevert(WTFStaking.NoActiveStake.selector);
        staking.unstake();
    }

    function testStakeAsEmployer() public {
        uint256 amount = 1500 * 1e18;

        wtfToken.mint(employer, amount);

        vm.startPrank(employer);

        wtfToken.approve(address(staking), amount);

        vm.expectEmit(true, false, false, true);
        emit WTFStaking.EmployerStaked(employer, amount, block.timestamp);

        staking.stakeAsEmployer(amount);

        vm.stopPrank();

        (uint256 storedAmount, uint256 stakedAt, bool active) = staking.employerStakes(employer);

        assertEq(storedAmount, amount);
        assertEq(stakedAt, block.timestamp);
        assertTrue(active);

        assertEq(staking.totalEmployerStaked(), amount);
        assertEq(wtfToken.balanceOf(address(staking)), amount);

        assertTrue(staking.isEmployerActive(employer));
    }

    function testStakeAsEmployerBelowMinimumReverts() public {
        uint256 amount = 999 * 1e18;

        wtfToken.mint(employer, amount);

        vm.prank(employer);

        vm.expectRevert(WTFStaking.EmployerStakeTooSmall.selector);
        staking.stakeAsEmployer(amount);
    }

    function testStakeAsEmployerAlreadyActiveReverts() public {
        uint256 amount = 1500 * 1e18;

        wtfToken.mint(employer, amount);

        vm.startPrank(employer);

        wtfToken.approve(address(staking), amount);

        staking.stakeAsEmployer(amount);

        vm.expectRevert(WTFStaking.AlreadyEmployerStaking.selector);
        staking.stakeAsEmployer(amount);

        vm.stopPrank();
    }

    function testUnstakeAsEmployer() public {
        uint256 amount = 1500 * 1e18;

        wtfToken.mint(employer, amount);

        vm.startPrank(employer);

        wtfToken.approve(address(staking), amount);

        staking.stakeAsEmployer(amount);

        vm.stopPrank();

        uint256 balanceBefore = wtfToken.balanceOf(employer);

        vm.expectEmit(true, false, false, true);
        emit WTFStaking.EmployerUnstaked(employer, amount, block.timestamp);

        vm.prank(employer);
        staking.unstakeAsEmployer();

        assertEq(wtfToken.balanceOf(employer), balanceBefore + amount);

        (uint256 storedAmount,, bool active) = staking.employerStakes(employer);

        assertEq(storedAmount, amount);
        assertFalse(active);

        assertEq(staking.totalEmployerStaked(), 0);
        assertFalse(staking.isEmployerActive(employer));
    }

    function testUnstakeAsEmployerWithoutActiveStakeReverts() public {
        vm.prank(employer);

        vm.expectRevert(WTFStaking.NoActiveEmployerStake.selector);
        staking.unstakeAsEmployer();
    }

    function testSetMinUserStake() public {
        uint256 newMin = 250 * 1e18;

        staking.setMinUserStake(newMin);

        assertEq(staking.minUserStake(), newMin);
    }

    function testSetMinEmployerStake() public {
        uint256 newMin = 2000 * 1e18;

        staking.setMinEmployerStake(newMin);

        assertEq(staking.minEmployerStake(), newMin);
    }

    function testSetYieldBoosterBps() public {
        uint256 newBps = 100;

        staking.setYieldBoosterBps(newBps);

        assertEq(staking.yieldBoosterBps(), newBps);
    }

    function testSetYieldBoosterAboveMaximumReverts() public {
        vm.expectRevert(WTFStaking.YieldBoosterTooHigh.selector);

        staking.setYieldBoosterBps(501);
    }

    function testWithdrawRewardPool() public {
        uint256 rewardAmount = 5000 * 1e18;

        wtfToken.mint(address(staking), rewardAmount);

        uint256 ownerBalanceBefore = wtfToken.balanceOf(address(this));

        staking.withdrawRewardPool(rewardAmount);

        assertEq(wtfToken.balanceOf(address(this)), ownerBalanceBefore + rewardAmount);

        assertEq(wtfToken.balanceOf(address(staking)), 0);
    }

    function testNonOwnerCannotSetMinUserStake() public {
        vm.prank(nonOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));

        staking.setMinUserStake(200 * 1e18);
    }

    function testNonOwnerCannotSetMinEmployerStake() public {
        vm.prank(nonOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));

        staking.setMinEmployerStake(2000 * 1e18);
    }

    function testNonOwnerCannotSetYieldBooster() public {
        vm.prank(nonOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));

        staking.setYieldBoosterBps(100);
    }

    function testNonOwnerCannotWithdrawRewardPool() public {
        uint256 rewardAmount = 5000 * 1e18;

        wtfToken.mint(address(staking), rewardAmount);

        vm.prank(nonOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));

        staking.withdrawRewardPool(rewardAmount);
    }

    function testDepositRewardPool() public {
        uint256 amount = 10000 * 1e18;

        wtfToken.mint(address(this), amount);

        wtfToken.approve(address(staking), amount);

        staking.depositRewardPool(amount);

        assertEq(wtfToken.balanceOf(address(staking)), amount);
    }

    function testNonOwnerCannotDepositRewardPool() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(nonOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));

        staking.depositRewardPool(amount);
    }
}

