// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IHealthCheck {
    function TYPE() external returns (uint256);

    function isPositionHealthy(address) external returns (bool);
}
