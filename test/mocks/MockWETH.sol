// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MockERC20} from "./MockERC20.sol";

/// @title MockWETH
/// @notice Mock implementation of WETH for testing
contract MockWETH is MockERC20 {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    constructor() MockERC20("Wrapped Ether", "WETH", 18) {}

    /// @notice Deposit ETH to get WETH
    function deposit() external payable {
        mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice Withdraw ETH from WETH
    function withdraw(uint256 amount) external {
        require(
            balanceOf[msg.sender] >= amount,
            "MockWETH: insufficient balance"
        );
        burn(msg.sender, amount);
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "MockWETH: ETH transfer failed");
        emit Withdrawal(msg.sender, amount);
    }

    receive() external payable {
        this.deposit();
    }
}
