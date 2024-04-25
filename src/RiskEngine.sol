// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import {Pool} from "./Pool.sol";
import {IPosition} from "./interface/IPosition.sol";
import {DebtData, AssetData} from "./PositionManager.sol";
import {IRiskModule} from "./interface/IRiskModule.sol";
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

    // liquidators buy position collateral at a discount by receiving a higher value of collateral
    // than debt repaid. the discount is a protocol parameter to incentivize liquidators while
    // ensuring efficient liquidations of risky positions. the value stored is scaled by 18 decimals
    uint256 public liqudiationDiscount;

    // pool managers are free to choose their own oracle, but it must be recognized by the protocol
    /// @notice check if an oracle is recognized by the protocol
    // map oracle to its corresponding asset, any value other than address(0) == true
    mapping(address oracle => mapping(address asset => bool isKnown)) public isKnownOracle;

    // each position type implements its own health check
    /// @notice fetch the health check implementations for each position type
    mapping(uint256 positionType => address riskModule) public riskModuleFor;

    // pool managers are free to choose LTVs for pool they own
    /// @notice fetch the ltv for a given asset in a pool
    mapping(address pool => mapping(address asset => uint256 ltv)) public ltvFor;

    // pool managers are free to choose oracles for assets in pools they own
    /// @notice fetch the oracle for a given asset in a pool
    mapping(address pool => mapping(address asset => address oracle)) internal oracleFor;

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event LtvBoundsSet(uint256 minLtv, uint256 maxLtv);
    event LiquidationDiscountSet(uint256 liqudiationDiscount);
    event RiskModuleSet(uint256 indexed positionType, address riskModule);
    event LtvSet(address indexed pool, address indexed asset, uint256 ltv);
    event OracleSet(address indexed pool, address indexed asset, address oracle);
    event OracleStatusSet(address indexed oracle, address indexed asset, bool isKnown);

    /*//////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/

    error RiskEngine_LtvLimitBreached(uint256 ltv);
    error RiskEngine_MissingRiskModule(uint256 positionType);
    error RiskEngine_NoOracleFound(address pool, address asset);
    error RiskEngine_OnlyPoolOwner(address pool, address sender);
    error RiskEngine_UnknownOracle(address oracle, address asset);

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _minLtv, uint256 _maxLtv, uint256 _liquidationDiscount) public initializer {
        OwnableUpgradeable.__Ownable_init(msg.sender);
        minLtv = _minLtv;
        maxLtv = _maxLtv;
        liqudiationDiscount = _liquidationDiscount;
    }

    /*//////////////////////////////////////////////////////////////
                           Public Functions
    //////////////////////////////////////////////////////////////*/

    function getOracleFor(address pool, address asset) public view returns (address) {
        address oracle = oracleFor[pool][asset];
        if (oracle == address(0)) revert RiskEngine_NoOracleFound(pool, asset);
        return oracle;
    }

    /// @notice check if a position is healthy
    /// @param position the position to check
    function isPositionHealthy(address position) external view returns (bool) {
        if (riskModuleFor[IPosition(position).TYPE()] == address(0)) {
            revert RiskEngine_MissingRiskModule(IPosition(position).TYPE());
        }

        // call health check implementation based on position type
        return IRiskModule(riskModuleFor[IPosition(position).TYPE()]).isPositionHealthy(position);
    }

    function isValidLiquidation(address position, DebtData[] calldata debt, AssetData[] calldata collat)
        external
        view
        returns (bool)
    {
        if (riskModuleFor[IPosition(position).TYPE()] == address(0)) {
            revert RiskEngine_MissingRiskModule(IPosition(position).TYPE());
        }

        // call health check implementation based on position type
        return IRiskModule(riskModuleFor[IPosition(position).TYPE()]).isValidLiquidation(
            position, debt, collat, liqudiationDiscount
        );
    }

    function getRiskData(address position) external view returns (uint256, uint256, uint256) {
        if (riskModuleFor[IPosition(position).TYPE()] == address(0)) {
            revert RiskEngine_MissingRiskModule(IPosition(position).TYPE());
        }

        return IRiskModule(riskModuleFor[IPosition(position).TYPE()]).getRiskData(position);
    }

    /*//////////////////////////////////////////////////////////////
                           Only Pool Owner
    //////////////////////////////////////////////////////////////*/

    /// @notice set ltv for a given asset in a pool
    /// @dev only pool owners can set the ltv for their pools
    /// @dev ltv is scaled by 18 decimals
    function setLtv(address pool, address asset, uint256 ltv) external {
        // only pool owners are allowed to set ltv
        if (msg.sender != Pool(pool).owner()) revert RiskEngine_OnlyPoolOwner(pool, msg.sender);

        // set oracle before ltv so risk modules don't have to explicitly check if an oracle exists
        if (oracleFor[pool][asset] == address(0)) revert RiskEngine_NoOracleFound(pool, asset);

        // ensure new ltv is witihin global limits or zero
        if ((ltv != 0 && ltv < minLtv) || ltv > maxLtv) revert RiskEngine_LtvLimitBreached(ltv);

        // update asset ltv for the given pool
        ltvFor[pool][asset] = ltv;

        emit LtvSet(pool, asset, ltv);
    }

    /// @notice set the oracle for a given asset in a pool
    /// @dev only pool owners can set the oracle for their pools
    function setOracle(address pool, address asset, address oracle) external {
        // revert if the oracle is not recognized by the protocol
        if (!isKnownOracle[oracle][asset]) revert RiskEngine_UnknownOracle(oracle, asset);

        // only pool owners are allowed to set oracles
        if (msg.sender != Pool(pool).owner()) revert RiskEngine_OnlyPoolOwner(pool, msg.sender);

        // update asset oracle for pool
        oracleFor[pool][asset] = oracle;

        emit OracleSet(pool, asset, oracle);
    }

    /*//////////////////////////////////////////////////////////////
                              Only Owner
    //////////////////////////////////////////////////////////////*/

    function setLiquidationDiscount(uint256 _liquidationDiscount) external onlyOwner {
        liqudiationDiscount = _liquidationDiscount;

        emit LiquidationDiscountSet(_liquidationDiscount);
    }

    function setLtvBounds(uint256 _minLtv, uint256 _maxLtv) external onlyOwner {
        minLtv = _minLtv;
        maxLtv = _maxLtv;

        emit LtvBoundsSet(_minLtv, _maxLtv);
    }

    /// @notice set the health check implementation for a given position type
    /// @dev only callable by RiskEngine owner
    /// @param positionType the type of position
    /// @param riskModule the address of the risk module implementation
    function setRiskModule(uint256 positionType, address riskModule) external onlyOwner {
        riskModuleFor[positionType] = riskModule;

        emit RiskModuleSet(positionType, riskModule);
    }

    /// @notice toggle whether a given oracle-asset pair is recognized by the protocol
    /// @dev only callable by RiskEngine owner
    /// @param oracle oracle address
    /// @param asset token address for the given oracle
    function toggleOracleStatus(address oracle, address asset) external onlyOwner {
        isKnownOracle[oracle][asset] = !isKnownOracle[oracle][asset];

        emit OracleStatusSet(oracle, asset, isKnownOracle[oracle][asset]);
    }
}
