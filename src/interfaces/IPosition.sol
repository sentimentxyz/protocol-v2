// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IPosistion {
    function exec(address target, bytes calldata data) external;

    function repay(address asset, uint256 amt) external;
    function borrow(address asset, uint256 amt) external;
    function deposit(address asset, uint256 amt) external;
    function withdraw(address asset, uint256 amt) external;
}
