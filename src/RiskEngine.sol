// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {Pool} from "./Pool.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {IHealthCheck} from "./interfaces/IHealthCheck.sol";
// contracts
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract RiskEngine is OwnableUpgradeable {
    error Unauthorized();
    error UnknownOracle();

    // pool managers are free to choose their own oracle but
    // these oracles must belong to a list of known oracles
    mapping(address oracle => bool isKnown) public oracleUniverse;

    // each position type implements its own health check
    mapping(uint256 positionType => address healthCheckImpl) public healthCheckFor;

    mapping(address pool => mapping(address asset => uint256 ltv)) public ltvFor;
    mapping(address pool => mapping(address asset => address oracle)) public oracleFor;

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        OwnableUpgradeable.__Ownable_init(msg.sender);
    }

    /// @notice checks if a position is healthy
    /// @param position the position to check
    function isPositionHealthy(address position) external returns (bool) {
        return IHealthCheck(healthCheckFor[IPosition(position).TYPE()]).isPositionHealthy(position);
    }

    /// @notice Sets the oracle for a pool and a token
    /// @dev only the pool owner can set the oracle
    /// @dev oracle must be pre approved
    function setOracle(address pool, address asset, address oracle) external {
        if (!oracleUniverse[oracle]) revert UnknownOracle();
        if (msg.sender != Pool(pool).owner()) revert Unauthorized();
        oracleFor[pool][asset] = oracle;
    }

    /// @notice sets the LTV for a given a pool and a token
    /// @dev callable only by the pool owner
    function setLtv(address pool, address asset, uint256 ltv) external {
        if (msg.sender != Pool(pool).owner()) revert Unauthorized();
        ltvFor[pool][asset] = ltv;
    }

    /// @notice callable only by the owner of the contract
    /// @dev sets the health check implementation for a given position type
    /// @param positionType the type of position
    /// @param healthCheckImpl the address of the health check implementation
    function setHealthCheck(uint256 positionType, address healthCheckImpl) external onlyOwner {
        healthCheckFor[positionType] = healthCheckImpl;
    }

    /// @dev callable only by the owner of the contract
    /// @param oracle the address of the oracle who status to negate
    function toggleOracleStatus(address oracle) external onlyOwner {
        oracleUniverse[oracle] = !oracleUniverse[oracle];
    }
}
