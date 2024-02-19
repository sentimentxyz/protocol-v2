// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Errors {
    error Unauthorized();
    error UnknownOracle();
    error PoolCapTooLow();
    error InvalidPoolAsset();
    error OnlyAllocatorOrOwner();
    error InvalidPool();
    error InvalidOperation();
    error HealthCheckFailed();
    error InvalidPositionType();
    error ZeroShares();
    error PositionManagerOnly();
    error HealthCheckImplNotFound();
    error UnknownContract();
}
