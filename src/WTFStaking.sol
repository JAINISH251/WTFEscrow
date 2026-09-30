// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WTFStaking is Ownable {
    // WTF token
    IERC20 public immutable wtfToken;

    // Staking configuration
    uint256 public minUserStake = 100 * 1e18;
    uint256 public minEmployerStake = 1000 * 1e18;
    uint256 public yieldBoosterBps = 50;

    // User staking data
    struct UserStake {
        uint256 amount;
        uint256 stakedAt;
        uint256 lastClaimedAt;
        bool active;
    }

    // Employer staking data
    struct EmployerStake {
        uint256 amount;
        uint256 stakedAt;
        bool active;
    }

    // Mappings
    mapping(address => UserStake) public userStakes;
    mapping(address => EmployerStake) public employerStakes;

    //State Variables
    uint256 public totalUserStaked = 0;
    uint256 public totalEmployerStaked = 0;

    // Events
    event UserStaked(address indexed user, uint256 amount, uint256 timestamp);

    event UserUnstaked(address indexed user, uint256 amount, uint256 timestamp);

    event UserRewardClaimed(address indexed user, uint256 rewardAmount, uint256 timestamp);

    event EmployerStaked(address indexed employer, uint256 amount, uint256 timestamp);

    event EmployerUnstaked(address indexed employer, uint256 amount, uint256 timestamp);

    event YieldBoosterUpdated(uint256 oldBps, uint256 newBps);

    //Error
    error StakeTooSmall();
    error AlreadyStaking();
    error TokenTransferFailed();
    error NoActiveStake();
error NoReward();
error EmployerStakeTooSmall();
error AlreadyEmployerStaking();
error NoActiveEmployerStake();
error YieldBoosterTooHigh();

    constructor(address _wtfToken) Ownable(msg.sender) {
        wtfToken = IERC20(_wtfToken);
    }

    // Functions

    function stake(uint256 amount) external {
        if (amount < minUserStake) {
            revert StakeTooSmall();
        }

        if (userStakes[msg.sender].active) {
            revert AlreadyStaking();
        }

                userStakes[msg.sender] =
            UserStake({amount: amount, stakedAt: block.timestamp, lastClaimedAt: block.timestamp, active: true});

        totalUserStaked += amount;

        emit UserStaked(msg.sender, amount, block.timestamp);

        bool success = wtfToken.transferFrom(msg.sender, address(this), amount);

        if (!success) {
            revert TokenTransferFailed();
        }


    }


    function _calculateReward(
    address user
) internal view returns (uint256) {
    UserStake memory stakeInfo = userStakes[user];

    if (!stakeInfo.active) {
        return 0;
    }

    uint256 elapsed = block.timestamp - stakeInfo.lastClaimedAt;

    return (
        stakeInfo.amount *
        yieldBoosterBps *
        elapsed
    ) / (10000 * 365 days);
}


function calculateReward(
    address user
) public view returns (uint256) {
    return _calculateReward(user);
}


    function claimReward() public {
    UserStake storage stakeInfo = userStakes[msg.sender];

    if (!stakeInfo.active) {
        revert NoActiveStake();
    }

    uint256 reward = _calculateReward(msg.sender);

    if (reward == 0) {
        revert NoReward();
    }

    stakeInfo.lastClaimedAt = block.timestamp;

    emit UserRewardClaimed(
        msg.sender,
        reward,
        block.timestamp
    );
    bool success = wtfToken.transfer(msg.sender, reward);

    if (!success) {
        revert TokenTransferFailed();
    }

}

function unstake() external {
    UserStake storage stakeInfo = userStakes[msg.sender];

    if (!stakeInfo.active) {
        revert NoActiveStake();
    }

    uint256 amount = stakeInfo.amount;

            emit UserUnstaked(
        msg.sender,
        amount,
        block.timestamp
    );

    // Auto-claim pending reward.
    uint256 reward = _calculateReward(msg.sender);

    if (reward > 0) {
        stakeInfo.lastClaimedAt = block.timestamp;

        emit UserRewardClaimed(
            msg.sender,
            reward,
            block.timestamp
        );
        bool rewardSuccess = wtfToken.transfer(msg.sender, reward);

        if (!rewardSuccess) {
            revert TokenTransferFailed();
        }

    }


    // Deactivate the user's stake.
    stakeInfo.active = false;
    totalUserStaked -= amount;


    // Return the principal.
    bool success = wtfToken.transfer(msg.sender, amount);

    if (!success) {
        revert TokenTransferFailed();
    }

}
// ====================
// EMPLOYER STAKING
// ====================

function stakeAsEmployer(uint256 amount) external {
    if (amount < minEmployerStake) {
        revert EmployerStakeTooSmall();
    }

    if (employerStakes[msg.sender].active) {
        revert AlreadyEmployerStaking();
    }

    totalEmployerStaked += amount;

    emit EmployerStaked(
        msg.sender,
        amount,
        block.timestamp
    );
    
     employerStakes[msg.sender] = EmployerStake({
        amount: amount,
        stakedAt: block.timestamp,
        active: true
    });

    bool success = wtfToken.transferFrom(
        msg.sender,
        address(this),
        amount
    );

    if (!success) {
        revert TokenTransferFailed();
    }

   
    
}

function unstakeAsEmployer() external {
    EmployerStake storage stakeInfo = employerStakes[msg.sender];

    if (!stakeInfo.active) {
        revert NoActiveEmployerStake();
    }

    uint256 amount = stakeInfo.amount;

    stakeInfo.active = false;

    totalEmployerStaked -= amount;

    emit EmployerUnstaked(
        msg.sender,
        amount,
        block.timestamp
    );
    bool success = wtfToken.transfer(msg.sender, amount);

    if (!success) {
        revert TokenTransferFailed();
    }

}

function isEmployerActive(
    address employer
) external view returns (bool) {
    return employerStakes[employer].active;
}

function getEmployerStake(
    address employer
) external view returns (EmployerStake memory) {
    return employerStakes[employer];
}





function setMinUserStake(uint256 newMin) external onlyOwner {
    minUserStake = newMin;
}

function setMinEmployerStake(uint256 newMin) external onlyOwner {
    minEmployerStake = newMin;
}

function setYieldBoosterBps(uint256 newBps) external onlyOwner {
    if (newBps > 500) {
        revert YieldBoosterTooHigh();
    }

    uint256 oldBps = yieldBoosterBps;

    yieldBoosterBps = newBps;

    emit YieldBoosterUpdated(oldBps, newBps);
}

function withdrawRewardPool(uint256 amount) external onlyOwner {
    bool success = wtfToken.transfer(owner(), amount);

    if (!success) {
        revert TokenTransferFailed();
    }
}

    // depositRewardPool

function depositRewardPool(uint256 amount) external onlyOwner {
    bool success = wtfToken.transferFrom(
        msg.sender,
        address(this),
        amount
    );

    if (!success) {
        revert TokenTransferFailed();
    }
}

}
