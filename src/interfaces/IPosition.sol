// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IPosition {
    // view functions
    function TYPE() external view returns (uint256);
    function owner() external view returns (address);
    function getAssets() external view returns (address[] memory);
    function getDebtPools() external view returns (address[] memory);

    function repay(address pool, uint256 amt) external;
    function borrow(address pool, uint256 amt) external;
    function withdraw(address asset, uint256 amt) external;
    function exec(address target, bytes calldata data) external;

    function addAsset(address asset) external;
    function removeAsset(address asset) external;
}
