// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPool} from "./interfaces/IPool.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {IHealthCheck} from "./interfaces/IHealthCheck.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RiskEngine is Ownable {
    mapping(address => mapping(address => uint256)) public ltvFor;
    mapping(address => mapping(address => address)) public oracleFor;

    mapping(uint256 => address) public healthCheckFor;

    error Unauthorized();

    constructor() Ownable(msg.sender) {}

    function isPositionHealthy(address position) external returns (bool) {
        return IHealthCheck(healthCheckFor[IPosition(position).TYPE()]).isPositionHealthy(position);
    }

    function setOracle(address pool, address asset, address oracle) external {
        if (msg.sender != IPool(pool).owner()) revert Unauthorized();
        oracleFor[pool][asset] = oracle;
    }

    function setLtv(address pool, address asset, uint256 ltv) external {
        if (msg.sender != IPool(pool).owner()) revert Unauthorized();
        ltvFor[pool][asset] = ltv;
    }

    function setHealthCheck(uint256 positionType, address healthCheckImpl) external onlyOwner {
        healthCheckFor[positionType] = healthCheckImpl;
    }
}
