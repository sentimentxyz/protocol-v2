// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IRiskManager {
    function isPositionHealthy(address position) external returns (bool);
}
