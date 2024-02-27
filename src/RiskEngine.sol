// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import {Pool} from "./Pool.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {DebtData, AssetData} from "./PositionManager.sol";
import {IHealthCheck} from "./interfaces/IHealthCheck.sol";
// libraries
import {Errors} from "src/lib/Errors.sol";
// contracts
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/*//////////////////////////////////////////////////////////////
                            RiskEngine
//////////////////////////////////////////////////////////////*/

contract RiskEngine is OwnableUpgradeable {
    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    // lenders are free to set their own ltv within the global protocol limits
    // the global limits can only be modified by the protocol
    // ltv updates revert if they fall beyond the bounds
    uint256 public minLtv;
    uint256 public maxLtv;

    uint256 public closeFactor;

    // liquidators buy position collateral at a discount by receiving a higher value of collateral
    // than debt repaid. the discount is a protocol parameter to incentivize liquidators while
    // ensuring efficient liquidations of risky positions. the value stored is scaled by 18 decimals
    uint256 public liqudiationDiscount;

    // pool managers are free to choose their own oracle, but it must be recognized by the protocol
    /// @notice check if an oracle is recognized by the protocol
    mapping(address oracle => bool isKnown) public isKnownOracle;

    // each position type implements its own health check
    /// @notice fetch the health check implementations for each position type
    mapping(uint256 positionType => address riskModule) public riskModuleFor;

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

    function initialize(uint256 _minLtv, uint256 _maxLtv) public initializer {
        OwnableUpgradeable.__Ownable_init(msg.sender);
        minLtv = _minLtv;
        maxLtv = _maxLtv;
    }

    /*//////////////////////////////////////////////////////////////
                           Public Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice check if a position is healthy
    /// @param position the position to check
    function isPositionHealthy(address position) external view returns (bool) {
        if (riskModuleFor[IPosition(position).TYPE()] == address(0)) revert Errors.NoHealthCheckImpl();

        // call health check implementation based on position type
        return IHealthCheck(riskModuleFor[IPosition(position).TYPE()]).isPositionHealthy(position);
    }

    function isValidLiquidation(address position, DebtData[] calldata debt, AssetData[] calldata collat)
        external
        view
        returns (bool)
    {
        if (riskModuleFor[IPosition(position).TYPE()] == address(0)) revert Errors.NoHealthCheckImpl();

        // call health check implementation based on position type
        return IHealthCheck(riskModuleFor[IPosition(position).TYPE()]).isValidLiquidation(
            position, debt, collat, liqudiationDiscount
        );
    }

    /*//////////////////////////////////////////////////////////////
                           Only Pool Owner
    //////////////////////////////////////////////////////////////*/

    /// @notice set ltv for a given asset in a pool
    /// @dev only pool owners can set the ltv for their pools
    /// @dev ltv is scaled by 18 decimals
    function setLtv(address pool, address asset, uint256 ltv) external {
        // only pool owners are allowed to set ltv
        if (msg.sender != Pool(pool).owner()) revert Errors.onlyPoolOwner();
        if (ltv < minLtv || ltv > maxLtv || ltv == 0) revert Errors.OutsideGlobalLtvLimits();

        // update asset ltv for the given pool
        ltvFor[pool][asset] = ltv;
    }

    /// @notice set the oracle for a given asset in a pool
    /// @dev only pool owners can set the oracle for their pools
    function setOracle(address pool, address asset, address oracle) external {
        // revert if the oracle is not recognized by the protocol
        if (!isKnownOracle[oracle]) revert Errors.UnknownOracle();

        // only pool owners are allowed to set oracles
        if (msg.sender != Pool(pool).owner()) revert Errors.onlyPoolOwner();

        // update asset oracle for pool
        oracleFor[pool][asset] = oracle;
    }

    /*//////////////////////////////////////////////////////////////
                              Only Owner
    //////////////////////////////////////////////////////////////*/

    function setCloseFactor(uint256 _closeFactor) external onlyOwner {
        closeFactor = _closeFactor;
    }

    function setLiquidationDiscount(uint256 _liquidationDiscount) external onlyOwner {
        liqudiationDiscount = _liquidationDiscount;
    }

    function setLtvBounds(uint256 _minLtv, uint256 _maxLtv) external onlyOwner {
        minLtv = _minLtv;
        maxLtv = _maxLtv;
    }

    /// @notice set the health check implementation for a given position type
    /// @dev only callable by RiskEngine owner
    /// @param positionType the type of position
    /// @param riskModule the address of the risk module implementation
    function setRiskModule(uint256 positionType, address riskModule) external onlyOwner {
        riskModuleFor[positionType] = riskModule;
    }

    /// @notice toggle whether a given oracle is recognized by the protocol
    /// @dev only callable by RiskEngine owner
    /// @param oracle the address of the oracle who status to negate
    function toggleOracleStatus(address oracle) external onlyOwner {
        isKnownOracle[oracle] = !isKnownOracle[oracle];
    }
}
