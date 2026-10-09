// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
/// @title StakingRewards
contract StakingRewardsVuln1 is ERC20 {
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;
    address public rewarder;
    uint256 public rewardPerShare;
    uint256 public totalDistributed;

    mapping(address => uint256) public rewardDebt;
    mapping(address => uint256) public claimedRewards;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardDistributed(uint256 amount, uint256 newRewardPerShare);
    event RewardClaimed(address indexed user, uint256 amount);
    constructor(address _staking, address _reward) ERC20("sToken", "sTKN") {
        stakingToken = IERC20(_staking);
        rewardToken = IERC20(_reward);
        rewarder = msg.sender;
    }
    /// @notice Stake tokens to earn rewards
    function stake(uint256 amount) external {
        require(amount > 0, "Cannot stake 0");
        require(stakingToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        _mint(msg.sender, amount);
        rewardDebt[msg.sender] = balanceOf(msg.sender) * rewardPerShare / 1e18;
        emit Staked(msg.sender, amount);
    }
    /// @notice Unstake and reclaim tokens
    function unstake(uint256 amount) external {
        require(amount > 0, "Cannot unstake 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient stake");
        _claimReward(msg.sender);
        _burn(msg.sender, amount);
        require(stakingToken.transfer(msg.sender, amount), "Transfer failed");
        rewardDebt[msg.sender] = balanceOf(msg.sender) * rewardPerShare / 1e18;
        emit Unstaked(msg.sender, amount);
    }
    /// @notice Distribute tokens to recipients
    function distributeReward(uint256 amount) external {
        require(msg.sender == rewarder, "Not rewarder");
        require(totalSupply() > 0, "No stakers");
        require(amount > 0, "Zero reward");
        require(rewardToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        rewardPerShare += amount * 1e18 / totalSupply();
        totalDistributed += amount;
        emit RewardDistributed(amount, rewardPerShare);
    }
    function _claimReward(address user) internal {
        uint256 pending = balanceOf(user) * rewardPerShare / 1e18 - rewardDebt[user];
        if (pending > 0) {
            require(rewardToken.transfer(user, pending), "Transfer failed");
            claimedRewards[user] += pending;
            emit RewardClaimed(user, pending);
        }
    }
    /// @notice Claim accumulated rewards
    function claimReward() external {
        _claimReward(msg.sender);
        rewardDebt[msg.sender] = balanceOf(msg.sender) * rewardPerShare / 1e18;
    }
    /// @notice Pending reward
    function pendingReward(address user) external view returns (uint256) {
        return balanceOf(user) * rewardPerShare / 1e18 - rewardDebt[user];
    }
    /// @notice Configure a contract parameter
    function setRewarder(address _rewarder) external {
        require(msg.sender == rewarder, "Not rewarder");
        rewarder = _rewarder;
    }
}


