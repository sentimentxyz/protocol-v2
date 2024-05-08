// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import {Pool} from "./Pool.sol";
import {Position} from "./Position.sol";
import {DebtData, AssetData} from "./PositionManager.sol";
import {RiskModule} from "./RiskModule.sol";
// contracts
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/*//////////////////////////////////////////////////////////////
                            RiskEngine
//////////////////////////////////////////////////////////////*/

contract RiskEngine is OwnableUpgradeable {
    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    uint256 public constant TIMELOCK_DURATION = 24 * 60 * 60; // 24 hours

    struct LtvUpdate {
        uint256 ltv;
        uint256 validAfter;
    }

    // lenders are free to set their own ltv within the global protocol limits
    // the global limits can only be modified by the protocol
    // ltv updates revert if they fall beyond the bounds
    uint256 public minLtv;
    uint256 public maxLtv;

    RiskModule public riskModule;

    /// @notice fetch the oracle for a given asset
    mapping(address asset => address oracle) internal oracleFor;

    // pool managers are free to choose LTVs for pool they own
    /// @notice fetch the ltv for a given asset in a pool
    mapping(address pool => mapping(address asset => uint256 ltv)) public ltvFor;
    mapping(address pool => mapping(address asset => LtvUpdate ltvUpdate)) public ltvUpdateFor;

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event RiskModuleSet(address riskModule);
    event LtvBoundsSet(uint256 minLtv, uint256 maxLtv);
    event OracleSet(address indexed asset, address oracle);
    event LiquidationDiscountSet(uint256 liqudiationDiscount);
    event LtvUpdateRejected(address indexed pool, address indexed asset);
    event LtvUpdateAccepted(address indexed pool, address indexed asset, uint256 ltv);
    event LtvUpdateRequested(address indexed pool, address indexed asset, LtvUpdate ltvUpdate);

    /*//////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/

    error RiskEngine_NoOracleFound(address asset);
    error RiskEngine_LtvLimitBreached(uint256 ltv);
    error RiskEngine_NoLtvUpdate(address pool, address asset);
    error RiskEngine_NoOracleUpdate(address pool, address asset);
    error RiskEngine_OnlyPoolOwner(address pool, address sender);
    error RiskEngine_UnknownOracle(address oracle, address asset);
    error RiskEngine_LtvUpdateTimelocked(address pool, address asset);
    error RiskEngine_OracleUpdateTimelocked(address pool, address asset);

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
                              Modifiers
    //////////////////////////////////////////////////////////////*/

    modifier onlyPoolOwner(address pool) {
        // only pool owners are allowed to set oracles
        if (msg.sender != Pool(pool).owner()) revert RiskEngine_OnlyPoolOwner(pool, msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           Public Functions
    //////////////////////////////////////////////////////////////*/

    function getOracleFor(address asset) public view returns (address) {
        address oracle = oracleFor[asset];
        if (oracle == address(0)) revert RiskEngine_NoOracleFound(asset);
        return oracle;
    }

    /// @notice check if a position is healthy
    /// @param position the position to check
    function isPositionHealthy(address position) external view returns (bool) {
        // call health check implementation based on position type
        return riskModule.isPositionHealthy(position);
    }

    function isValidLiquidation(address position, DebtData[] calldata debt, AssetData[] calldata collat)
        external
        view
        returns (bool)
    {
        // call health check implementation based on position type
        return riskModule.isValidLiquidation(position, debt, collat);
    }

    function getRiskData(address position) external view returns (uint256, uint256, uint256) {
        return riskModule.getRiskData(position);
    }

    /*//////////////////////////////////////////////////////////////
                              LTV Update
    //////////////////////////////////////////////////////////////*/

    function requestLtvUpdate(address pool, address asset, uint256 ltv) external onlyPoolOwner(pool) {
        // set oracle before ltv so risk modules don't have to explicitly check if an oracle exists
        if (oracleFor[asset] == address(0)) revert RiskEngine_NoOracleFound(asset);

        // ensure new ltv is witihin global limits or zero
        if ((ltv != 0 && ltv < minLtv) || ltv > maxLtv) revert RiskEngine_LtvLimitBreached(ltv);

        LtvUpdate memory ltvUpdate;
        // only modification and removal of previously set ltvs require a timelock
        if (ltvFor[pool][asset] == 0) ltvUpdate = LtvUpdate({ltv: ltv, validAfter: block.timestamp});
        else ltvUpdate = LtvUpdate({ltv: ltv, validAfter: block.timestamp + TIMELOCK_DURATION});

        ltvUpdateFor[pool][asset] = ltvUpdate;

        emit LtvUpdateRequested(pool, asset, ltvUpdate);
    }

    function acceptLtvUpdate(address pool, address asset) external onlyPoolOwner(pool) {
        LtvUpdate memory ltvUpdate = ltvUpdateFor[pool][asset];

        if (ltvUpdate.validAfter == 0) revert RiskEngine_NoLtvUpdate(pool, asset);

        if (ltvUpdate.validAfter > block.timestamp) {
            revert RiskEngine_LtvUpdateTimelocked(pool, asset);
        }

        ltvFor[pool][asset] = ltvUpdate.ltv;

        emit LtvUpdateAccepted(pool, asset, ltvUpdate.ltv);
    }

    function rejectLtvUpdate(address pool, address asset) external onlyPoolOwner(pool) {
        delete ltvUpdateFor[pool][asset];

        emit LtvUpdateRejected(pool, asset);
    }

    /*//////////////////////////////////////////////////////////////
                              Only Owner
    //////////////////////////////////////////////////////////////*/

    function setLtvBounds(uint256 _minLtv, uint256 _maxLtv) external onlyOwner {
        minLtv = _minLtv;
        maxLtv = _maxLtv;

        emit LtvBoundsSet(_minLtv, _maxLtv);
    }

    /// @notice set the risk module used to store risk logic for positions
    /// @dev only callable by RiskEngine owner
    /// @param _riskModule the address of the risk module implementation
    function setRiskModule(address _riskModule) external onlyOwner {
        riskModule = RiskModule(_riskModule);

        emit RiskModuleSet(_riskModule);
    }

    function setOracle(address asset, address oracle) external onlyOwner {
        oracleFor[asset] = oracle;

        emit OracleSet(asset, oracle);
    }
}
