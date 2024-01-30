// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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

    function isPositionHealthy(address position) external returns (bool) {
        return IHealthCheck(healthCheckFor[IPosition(position).TYPE()]).isPositionHealthy(position);
    }

    function setOracle(address pool, address asset, address oracle) external {
        if (!oracleUniverse[oracle]) revert UnknownOracle();
        if (msg.sender != Pool(pool).owner()) revert Unauthorized();
        oracleFor[pool][asset] = oracle;
    }

    function setLtv(address pool, address asset, uint256 ltv) external {
        if (msg.sender != Pool(pool).owner()) revert Unauthorized();
        ltvFor[pool][asset] = ltv;
    }

    function setHealthCheck(uint256 positionType, address healthCheckImpl) external onlyOwner {
        healthCheckFor[positionType] = healthCheckImpl;
    }

    function toggleOracleStatus(address oracle) external onlyOwner {
        oracleUniverse[oracle] = !oracleUniverse[oracle];
    }
}
