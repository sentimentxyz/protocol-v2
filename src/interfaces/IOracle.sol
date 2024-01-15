// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IOracle {
    /// @dev returns the value of the asset in ETH wei
    function value(address asset, uint256 amount) external view returns (uint256);
}
