// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IPool {
    // Pool functions
    function asset() external view returns (address);
    function borrow(address position, uint256 amt) external;
    function getBorrowsOf(address position) external view returns (uint256);
    function repay(address position, uint256 amt) external returns (uint256);
    function convertToWei(address asset, uint256 amt) external view returns (uint256);
}
