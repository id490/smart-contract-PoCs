# Missing Order Deadline

## Vulnerability Summary

The DEX limit order does not contain a deadline. Once Alice signs an order, it remains executable until it is filled or cancelled, even if months have passed.

## Vulnerable Code

```solidity
struct Order {
    address maker;
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 minAmountOut;
}
```

The signed hash contains no expiry:

```solidity
bytes32 orderHash = keccak256(abi.encode(
    order.maker,
    order.tokenIn,
    order.tokenOut,
    order.amountIn,
    order.minAmountOut
));
```

`fillOrder()` also has no `block.timestamp` check.

## Root Cause

The maker's signature is not bound to a time window.

Alice may intend the order to be valid for only one hour, but the contract has no way to know that. The signature remains valid indefinitely.

## Attack / Failure Scenario

1. Alice creates an order to sell 10 WETH for at least 20,000 USDC.
2. Alice forgets about the order.
3. The order remains available off-chain.
4. 90 days later, 10 WETH is worth 40,000 USDC.
5. Someone fills Alice's old order for the original minimum of 20,000 USDC.
6. Alice receives 20,000 USDC instead of the current ~40,000 USDC value.

Alice has an approximate **20,000 USDC opportunity loss**.

## Proof of Concept



The Foundry PoC advances the timestamp by 90 days and then successfully calls:

https://github.com/id490/smart-contract-PoCs/blob/main/test/DexOrderBookDeadline.t.sol
```solidity
book.fillOrder(
    order,
    MIN_USDC,
    signature
);
```

The transaction succeeds even though the maker's intended one-hour window has long expired:

<img width="817" height="161" alt="image" src="https://github.com/user-attachments/assets/296404e6-fb7b-4b4b-8f93-a98d44e9c01b" />


## Impact

Stale signed orders can be executed long after the maker intended them to remain active, potentially causing significant losses when market prices move.

## Recommended Mitigation

Add a deadline to the signed order:

```solidity
struct Order {
    address maker;
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 minAmountOut;
    uint256 deadline;
}
```

Include `deadline` in the signed hash and enforce:

```solidity
require(block.timestamp <= order.deadline, "Order expired");
```

## Security Consideration

The deadline must be part of the signed data. Adding a deadline only to `fillOrder()` without signing it would not prevent the same replay.
