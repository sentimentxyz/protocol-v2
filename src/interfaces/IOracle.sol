// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IOracle {
    function getValueInEth(address asset, uint256 amt) external view returns (uint256);
}
