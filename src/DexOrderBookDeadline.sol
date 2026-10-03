// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";


/// @title LimitOrderBook
contract LimitOrderBook {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    mapping(bytes32 => bool) public filledOrders;
    struct Order {
        address maker;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
    }
    /// @notice Fill order
    /// @param order Order value
    /// @param amountOut Output token amount
    /// @param signature Cryptographic signature
    function fillOrder(
        Order calldata order,
        uint256 amountOut,
        bytes memory signature
    ) external {
        bytes32 orderHash = keccak256(abi.encode(
            order.maker, order.tokenIn, order.tokenOut,
            order.amountIn, order.minAmountOut
        ));
        require(!filledOrders[orderHash], "Already filled");
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(orderHash);
        require(ethHash.recover(signature) == order.maker, "Bad sig");
        require(amountOut >= order.minAmountOut, "Slippage");
        filledOrders[orderHash] = true;
        IERC20(order.tokenIn).safeTransferFrom(order.maker, msg.sender, order.amountIn);
        IERC20(order.tokenOut).safeTransferFrom(msg.sender, order.maker, amountOut);
    }
    /// @notice Cancel a pending operation
    function cancelOrder(Order calldata order) external {
        require(msg.sender == order.maker, "Not maker");
        bytes32 orderHash = keccak256(abi.encode(
            order.maker, order.tokenIn, order.tokenOut,
            order.amountIn, order.minAmountOut
        ));
        filledOrders[orderHash] = true;
    }
    /// @notice Is order filled
    function isOrderFilled(bytes32 hash) external view returns (bool) {
        return filledOrders[hash];
    }
}

