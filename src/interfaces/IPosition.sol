// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPosition {
    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/
    function TYPE() external view returns (uint256);
    function getAssets() external view returns (address[] memory);
    function getDebtPools() external view returns (address[] memory);

    /*//////////////////////////////////////////////////////////////
                       State Mutating Functions
    //////////////////////////////////////////////////////////////*/
    function addAsset(address asset) external;
    function removeAsset(address asset) external;
    function repay(address pool, uint256 amt) external;
    function borrow(address pool, uint256 amt) external;
    function exec(address target, bytes calldata data) external;
    function transfer(address to, address asset, uint256 amt) external;
    function approve(address token, address spender, uint256 amt) external;
}
