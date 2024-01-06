// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

abstract contract BasePosition {
    address public owner;
    address public positionManager;

    error InvalidOperation();
    error PositionManagerOnly();

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert PositionManagerOnly();
        _;
    }

    function TYPE() external view virtual returns (uint256);
    function getAssets() external view virtual returns (address[] memory);
    function getDebtPools() external view virtual returns (address[] memory);

    function repay(address pool, uint256 amt) external virtual;
    function borrow(address pool, uint256 amt) external virtual;
    function deposit(address asset, uint256 amt) external virtual;
    function withdraw(address asset, uint256 amt) external virtual;
    function exec(address target, bytes calldata data) external virtual;
}
