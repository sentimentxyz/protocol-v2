// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IRiskEngine {
    function ltvFor(address, address) external returns (uint256);
    function oracleFor(address, address) external returns (address);
    function isPositionHealthy(address position) external returns (bool);
}
