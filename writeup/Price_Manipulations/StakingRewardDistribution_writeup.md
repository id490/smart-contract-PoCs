# Last-Minute Staking Captures Disproportionate Rewards

Source: https://github.com/id490/smart-contract-PoCs/blob/main/src/StakingRewardDistribution1.sol


Proof of Concept : https://github.com/id490/smart-contract-PoCs/blob/main/test/StakingRewardDistribution1.t.sol
## Summary

`distributeReward()` allocates rewards based on the staking balance at the moment of distribution. An Front-runner can stake just before a reward distribution, capture a large share, and then unstake—even though the existing users have been staking for six months.

## Root Cause

```solidity
rewardPerShare += amount * 1e18 / totalSupply();
```

The contract divides the reward among the current stakers. It does not account for how long each user has staked or whether they were eligible before the reward distribution.

## Exploit Path

1. Alice, Bob, and Carol have staked a combined **1,000 sTKN for six months**. The rewarder is about to distribute **100 RWD**.
2. The attacker front-runs the transaction staking **9,000 sTKN** immediately before distribution, bringing the total stake to **10,000 sTKN**.
3. The reward per share becomes `100e18 * 1e18 / 10,000e18 = 1e16`, or **0.01 RWD per sTKN**.
4. The attacker receives **90 RWD**. Alice, Bob, and Carol receive just **10 RWD combined**.
5. The attacker unstakes and recovers the 9,000 sTKN, keeping the reward after staking only briefly.

| User | Stake at distribution | RWD received |
|---|---:|---:|
| Alice | 400 sTKN | 4 |
| Bob | 300 sTKN | 3 |
| Carol | 300 sTKN | 3 |
| Hacker | 9,000 sTKN | 90 |

## Impact

If rewards are intended for long-term or previously eligible stakers, the attacker diverts rewards from users who have been staking for six months. In the PoC, the hacker receives 90 of the 100 RWD distributed.

## Recommendation

Define reward eligibility explicitly. For duration-based rewards, distribute rewards over time and checkpoint each user's accrued rewards before changing their stake. If a reward is intended for existing stakers only, snapshot eligible balances before the distribution period begins.
