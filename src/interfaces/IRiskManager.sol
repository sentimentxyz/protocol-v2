// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IRiskManager {
    error PoolType();

    function isPositionHealthy(address position) external returns (bool);

    function ltv(address position, address pool, address token) external returns (uint256);
}
