// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IHealthCheck {
    function isPositionHealthy(address) external returns (bool);
}
