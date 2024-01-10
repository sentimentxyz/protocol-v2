// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IPositionManager {
    function repay(address position, address asset, uint256 amt) external;
    function borrow(address position, address asset, uint256 amt) external;
    function deposit(address position, address asset, uint256 amt) external;
    function withdraw(address position, address asset, uint256 amt) external;

    function liquidate(address position) external;
    function exec(address position, bytes calldata data) external;
    function approve(address position, address asset, uint256 amt) external;
}
