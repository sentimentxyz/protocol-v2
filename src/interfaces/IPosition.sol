// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IPosistion {
    // view functions
    function getAssets() external view returns (address[] memory);
    function getDebtPools() external view returns (address[] memory);

    function repay(address asset, uint256 amt) external;
    function borrow(address asset, uint256 amt) external;
    function deposit(address asset, uint256 amt) external;
    function withdraw(address asset, uint256 amt) external;
    function exec(address target, bytes calldata data) external;
}
