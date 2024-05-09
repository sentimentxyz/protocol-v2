// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPosition {
    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/
    function TYPE() external view returns (uint256 positionType);
    function getAssets() external view returns (address[] memory assets);
    function getDebtPools() external view returns (address[] memory debtPool);

    /*//////////////////////////////////////////////////////////////
                       State Mutating Functions
    //////////////////////////////////////////////////////////////*/
    function addAsset(address asset) external;
    function removeAsset(address asset) external;
    function repay(uint256 poolId, uint256 amt) external;
    function borrow(uint256 poolId, uint256 amt) external;
    function exec(address target, bytes calldata data) external;
    function transfer(address to, address asset, uint256 amt) external;
    function approve(address token, address spender, uint256 amt) external;
}
