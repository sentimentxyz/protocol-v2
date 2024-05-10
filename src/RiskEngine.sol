// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import {Pool} from "./Pool.sol";
import {Registry} from "./Registry.sol";
import {Position} from "./Position.sol";
import {DebtData, AssetData} from "./PositionManager.sol";
import {RiskModule} from "./RiskModule.sol";
// contracts
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*//////////////////////////////////////////////////////////////
                            RiskEngine
//////////////////////////////////////////////////////////////*/

contract RiskEngine is Ownable {
    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    uint256 public constant TIMELOCK_DURATION = 24 * 60 * 60; // 24 hours
    // keccak(SENTIMENT_POOL_KEY)
    bytes32 public constant SENTIMENT_POOL_KEY = 0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728;
    // keccak(SENTIMENT_RISK_MODULE_KEY)
    bytes32 public constant SENTIMENT_RISK_MODULE_KEY =
        0x881469d14b8443f6c918bdd0a641e9d7cae2592dc28a4f922a2c4d7ca3d19c77;

    struct LtvUpdate {
        uint256 ltv;
        uint256 validAfter;
    }

    Registry public registry;

    // lenders are free to set their own ltv within the global protocol limits
    // the global limits can only be modified by the protocol
    // ltv updates revert if they fall beyond the bounds
    uint256 public minLtv;
    uint256 public maxLtv;

    Pool public pool;
    RiskModule public riskModule;

    /// @notice fetch the oracle for a given asset
    mapping(address asset => address oracle) internal oracleFor;

    // pool managers are free to choose LTVs for pool they own
    /// @notice fetch the ltv for a given asset in a pool
    mapping(uint256 poolId => mapping(address asset => uint256 ltv)) public ltvFor;
    mapping(uint256 poolId => mapping(address asset => LtvUpdate ltvUpdate)) public ltvUpdateFor;

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event PoolSet(address pool);
    event RiskModuleSet(address riskModule);
    event LtvBoundsSet(uint256 minLtv, uint256 maxLtv);
    event OracleSet(address indexed asset, address oracle);
    event LiquidationDiscountSet(uint256 liqudiationDiscount);
    event LtvUpdateRejected(uint256 indexed poolId, address indexed asset);
    event LtvUpdateAccepted(uint256 indexed poolId, address indexed asset, uint256 ltv);
    event LtvUpdateRequested(uint256 indexed poolId, address indexed asset, LtvUpdate ltvUpdate);

    /*//////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/

    error RiskEngine_AlreadyInitialized();
    error RiskEngine_NoOracleFound(address asset);
    error RiskEngine_LtvLimitBreached(uint256 ltv);
    error RiskEngine_NoLtvUpdate(uint256 poolId, address asset);
    error RiskEngine_NoOracleUpdate(uint256 poolId, address asset);
    error RiskEngine_OnlyPoolOwner(uint256 poolId, address sender);
    error RiskEngine_UnknownOracle(address oracle, address asset);
    error RiskEngine_LtvUpdateTimelocked(uint256 poolId, address asset);
    error RiskEngine_OracleUpdateTimelocked(uint256 poolId, address asset);

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    struct RiskEngineInitParams {
        address pool;
        address riskModule;
        uint256 minLtv;
        uint256 maxLtv;
    }

    constructor(address registry_, uint256 minLtv_, uint256 maxLtv_) Ownable(msg.sender) {
        registry = Registry(registry_);
        minLtv = minLtv_;
        maxLtv = maxLtv_;

        emit LtvBoundsSet(minLtv_, maxLtv_);
    }

    function updateFromRegistry() external {
        pool = Pool(registry.addressFor(SENTIMENT_POOL_KEY));
        riskModule = RiskModule(registry.addressFor(SENTIMENT_RISK_MODULE_KEY));

        emit PoolSet(address(pool));
        emit RiskModuleSet(address(riskModule));
    }

    /*//////////////////////////////////////////////////////////////
                              Modifiers
    //////////////////////////////////////////////////////////////*/

    modifier onlyPoolOwner(uint256 poolId) {
        // only pool owners are allowed to set oracles
        if (msg.sender != pool.ownerOf(poolId)) revert RiskEngine_OnlyPoolOwner(poolId, msg.sender);
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

    function validateLiquidation(DebtData[] calldata debt, AssetData[] calldata collat) external view {
        riskModule.validateLiquidation(debt, collat);
    }

    function getRiskData(address position) external view returns (uint256, uint256, uint256) {
        return riskModule.getRiskData(position);
    }

    /*//////////////////////////////////////////////////////////////
                              LTV Update
    //////////////////////////////////////////////////////////////*/

    function requestLtvUpdate(uint256 poolId, address asset, uint256 ltv) external onlyPoolOwner(poolId) {
        // set oracle before ltv so risk modules don't have to explicitly check if an oracle exists
        if (oracleFor[asset] == address(0)) revert RiskEngine_NoOracleFound(asset);

        // ensure new ltv is witihin global limits or zero
        if ((ltv != 0 && ltv < minLtv) || ltv > maxLtv) revert RiskEngine_LtvLimitBreached(ltv);

        LtvUpdate memory ltvUpdate;
        // only modification and removal of previously set ltvs require a timelock
        if (ltvFor[poolId][asset] == 0) ltvUpdate = LtvUpdate({ltv: ltv, validAfter: block.timestamp});
        else ltvUpdate = LtvUpdate({ltv: ltv, validAfter: block.timestamp + TIMELOCK_DURATION});

        ltvUpdateFor[poolId][asset] = ltvUpdate;

        emit LtvUpdateRequested(poolId, asset, ltvUpdate);
    }

    function acceptLtvUpdate(uint256 poolId, address asset) external onlyPoolOwner(poolId) {
        LtvUpdate memory ltvUpdate = ltvUpdateFor[poolId][asset];

        if (ltvUpdate.validAfter == 0) revert RiskEngine_NoLtvUpdate(poolId, asset);

        if (ltvUpdate.validAfter > block.timestamp) {
            revert RiskEngine_LtvUpdateTimelocked(poolId, asset);
        }

        ltvFor[poolId][asset] = ltvUpdate.ltv;

        emit LtvUpdateAccepted(poolId, asset, ltvUpdate.ltv);
    }

    function rejectLtvUpdate(uint256 poolId, address asset) external onlyPoolOwner(poolId) {
        delete ltvUpdateFor[poolId][asset];

        emit LtvUpdateRejected(poolId, asset);
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

    function setPool(address _pool) external onlyOwner {
        pool = Pool(_pool);

        emit PoolSet(_pool);
    }
}
