// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {Pool} from "./Pool.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {IHealthCheck} from "./interfaces/IHealthCheck.sol";
// libraries
import {Errors} from "src/lib/Errors.sol";
// contracts
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract RiskEngine is OwnableUpgradeable {
    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    // pool managers are free to choose their own oracle, but it must be recognized by the protocol
    /// @notice check if an oracle is recognized by the protocol
    mapping(address oracle => bool isKnown) public isKnownOracle;

    // each position type implements its own health check
    /// @notice fetch the health check implementations for each position type
    mapping(uint256 positionType => address healthCheckImpl) public healthCheckFor;

    // pool managers are free to choose LTVs for pool they own
    /// @notice fetch the ltv for a given asset in a pool
    mapping(address pool => mapping(address asset => uint256 ltv)) public ltvFor;

    // pool managers are free to choose oracles for assets in pools they own
    /// @notice fetch the oracle for a given asset in a pool
    mapping(address pool => mapping(address asset => address oracle)) public oracleFor;

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        OwnableUpgradeable.__Ownable_init(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                           Public Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice check if a position is healthy
    /// @param position the position to check
    function isPositionHealthy(address position) external view returns (bool) {
        // TODO revert with error if health check impl does not exist

        // call health check implementation based on position type
        return IHealthCheck(healthCheckFor[IPosition(position).TYPE()]).isPositionHealthy(position);
    }

    /*//////////////////////////////////////////////////////////////
                           Only Pool Owner
    //////////////////////////////////////////////////////////////*/

    /// @notice set ltv for a given asset in a pool
    /// @dev only pool owners can set the ltv for their pools
    /// @dev ltv is scaled by 18 decimals
    function setLtv(address pool, address asset, uint256 ltv) external {
        // only pool owners are allowed to set ltv
        if (msg.sender != Pool(pool).owner()) revert Errors.Unauthorized();

        // update asset ltv for the given pool
        ltvFor[pool][asset] = ltv;
    }

    /// @notice set the oracle for a given asset in a pool
    /// @dev only pool owners can set the oracle for their pools
    function setOracle(address pool, address asset, address oracle) external {
        // revert if the oracle is not recognized by the protocol
        if (!isKnownOracle[oracle]) revert Errors.UnknownOracle();

        // only pool owners are allowed to set oracles
        if (msg.sender != Pool(pool).owner()) revert Errors.Unauthorized();

        // update asset oracle for pool
        oracleFor[pool][asset] = oracle;
    }

    /*//////////////////////////////////////////////////////////////
                              Only Owner
    //////////////////////////////////////////////////////////////*/

    /// @notice set the health check implementation for a given position type
    /// @dev only callable by RiskEngine owner
    /// @param positionType the type of position
    /// @param healthCheckImpl the address of the health check implementation
    function setHealthCheck(uint256 positionType, address healthCheckImpl) external onlyOwner {
        healthCheckFor[positionType] = healthCheckImpl;
    }

    /// @notice toggle whether a given oracle is recognized by the protocol
    /// @dev only callable by RiskEngine owner
    /// @param oracle the address of the oracle who status to negate
    function toggleOracleStatus(address oracle) external onlyOwner {
        isKnownOracle[oracle] = !isKnownOracle[oracle];
    }
}
