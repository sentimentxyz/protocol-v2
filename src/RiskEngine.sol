// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// types
import {Pool} from "./Pool.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {IHealthCheck} from "./interfaces/IHealthCheck.sol";
// contracts
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RiskEngine is Ownable {
    error Unauthorized();

    mapping(address pool => mapping(address asset => uint256 ltv)) public ltvFor;
    mapping(uint256 positionType => address healthCheckImpl) public healthCheckFor;
    mapping(address pool => mapping(address asset => address oracle)) public oracleFor;

    constructor() Ownable(msg.sender) {}

    function isPositionHealthy(address position) external returns (bool) {
        return IHealthCheck(healthCheckFor[IPosition(position).TYPE()]).isPositionHealthy(position);
    }

    function setOracle(address pool, address asset, address oracle) external {
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
}
