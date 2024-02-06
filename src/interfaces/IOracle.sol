// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IOracle {
    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    function getValueInEth(address asset, uint256 amt) external view returns (uint256);
}
