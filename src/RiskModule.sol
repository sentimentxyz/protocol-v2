// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {Pool} from "./Pool.sol";
import {Position} from "./Position.sol";
import {Registry} from "./Registry.sol";
import {RiskEngine} from "./RiskEngine.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {DebtData, AssetData} from "./PositionManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract RiskModule {
    using Math for uint256;

    uint256 public constant VERSION = 1;

    // keccak(SENTIMENT_POOL_KEY)
    bytes32 public constant SENTIMENT_POOL_KEY = 0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728;
    // keccak(SENTIMENT_RISK_ENGINE_KEY)
    bytes32 public constant SENTIMENT_RISK_ENGINE_KEY =
        0x5b6696788621a5d6b5e3b02a69896b9dd824ebf1631584f038a393c29b6d7555;

    uint256 public immutable MIN_DEBT;
    uint256 public immutable LIQUIDATION_DISCOUNT;

    Registry public immutable REGISTRY;

    Pool public pool;
    RiskEngine public riskEngine;

    error RiskModule_SeizedTooMuch(uint256 seizedValue, uint256 maxSeizedValue);
    error RiskModule_DebtTooLow(address position);
    error RiskModule_ZeroAssetsWithDebt(address position);

    constructor(address registry_, uint256 minDebt_, uint256 liquidationDiscount_) {
        REGISTRY = Registry(registry_);
        MIN_DEBT = minDebt_;
        LIQUIDATION_DISCOUNT = liquidationDiscount_;
    }

    function updateFromRegistry() external {
        pool = Pool(REGISTRY.addressFor(SENTIMENT_POOL_KEY));
        riskEngine = RiskEngine(REGISTRY.addressFor(SENTIMENT_RISK_ENGINE_KEY));
    }

    function isPositionHealthy(address position) external view returns (bool) {
        if (Position(position).getDebtPools().length == 0) {
            return true;
        }
        (uint256 totalAssetValue, uint256 totalDebtValue, uint256 minReqAssetValue) = getRiskData(position);

        if (totalDebtValue != 0 && totalDebtValue < MIN_DEBT) revert RiskModule_DebtTooLow(position);
        if (totalAssetValue == 0 && totalDebtValue != 0) revert RiskModule_ZeroAssetsWithDebt(position);

        return totalAssetValue >= minReqAssetValue;
    }

    function getRiskData(address position) public view returns (uint256, uint256, uint256) {
        (uint256 totalAssetValue, address[] memory positionAssets, uint256[] memory positionAssetWeight) =
            _getPositionAssetData(position);

        (uint256 totalDebtValue, uint256[] memory debtPools, uint256[] memory debtValueForPool) =
            _getPositionDebtData(position);

        if (totalDebtValue == 0) return (totalAssetValue, 0, 0);

        uint256[] memory compositeLtvForPool = _getCompositeLtvForPool(debtPools, positionAssets, positionAssetWeight);

        uint256 minReqAssetValue = _getMinReqAssetValue(debtValueForPool, compositeLtvForPool);

        return (totalAssetValue, totalDebtValue, minReqAssetValue);
    }

    function validateLiquidation(DebtData[] calldata debt, AssetData[] calldata positionAsset) external view {
        uint256 debtRepaidValue;
        for (uint256 i; i < debt.length; ++i) {
            // PositionManger.liquidate() verifies that the asset belongs to the associated pool
            IOracle oracle = IOracle(riskEngine.getOracleFor(debt[i].asset));
            debtRepaidValue += oracle.getValueInEth(debt[i].asset, debt[i].amt);
        }

        uint256 assetSeizedValue;
        for (uint256 i; i < positionAsset.length; ++i) {
            IOracle oracle = IOracle(riskEngine.getOracleFor(positionAsset[i].asset));
            assetSeizedValue += oracle.getValueInEth(positionAsset[i].asset, positionAsset[i].amt);
        }

        // max asset value that can be seized by the liquidator
        uint256 maxSeizedAssetValue = debtRepaidValue.mulDiv((1e18 + LIQUIDATION_DISCOUNT), 1e18);

        if (assetSeizedValue > maxSeizedAssetValue) {
            revert RiskModule_SeizedTooMuch(assetSeizedValue, maxSeizedAssetValue);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          Position Debt Math
    //////////////////////////////////////////////////////////////*/

    function getDebtValueForPool(address position, uint256 poolId) public view returns (uint256) {
        address asset = pool.getPoolAssetFor(poolId);
        IOracle oracle = IOracle(riskEngine.getOracleFor(asset));
        return oracle.getValueInEth(asset, pool.getBorrowsOf(poolId, position));
    }

    function getTotalDebtValue(address position) public view returns (uint256) {
        uint256[] memory debtPools = Position(position).getDebtPools();

        uint256 totalDebtValue;
        for (uint256 i; i < debtPools.length; ++i) {
            totalDebtValue += getDebtValueForPool(position, debtPools[i]);
        }

        return totalDebtValue;
    }

    /*//////////////////////////////////////////////////////////////
                         Position Asset Math
    //////////////////////////////////////////////////////////////*/

    function getAssetValue(address position, address asset) public view returns (uint256) {
        IOracle oracle = IOracle(riskEngine.getOracleFor(asset));
        uint256 amt = IERC20(asset).balanceOf(position);
        return oracle.getValueInEth(asset, amt);
    }

    function getTotalAssetValue(address position) public view returns (uint256) {
        address[] memory positionAssets = Position(position).getPositionAssets();

        uint256 totalAssetValue;
        for (uint256 i; i < positionAssets.length; ++i) {
            totalAssetValue += getAssetValue(position, positionAssets[i]);
        }

        return totalAssetValue;
    }

    /*//////////////////////////////////////////////////////////////
                               Internal
    //////////////////////////////////////////////////////////////*/

    function _getPositionDebtData(address position)
        internal
        view
        returns (uint256, uint256[] memory, uint256[] memory)
    {
        uint256 totalDebtValue;
        uint256[] memory debtPools = Position(position).getDebtPools();
        if (debtPools.length == 0) {
            return(0, debtPools, new uint256[](0));
        }
        uint256[] memory debtValueForPool = new uint256[](debtPools.length);
        for (uint256 i; i < debtPools.length; ++i) {
            uint256 debt = getDebtValueForPool(position, debtPools[i]);
            debtValueForPool[i] = debt;
            totalDebtValue += debt;
        }

        return (totalDebtValue, debtPools, debtValueForPool);
    }

    function _getPositionAssetData(address position)
        internal
        view
        returns (uint256, address[] memory, uint256[] memory)
    {
        uint256 totalAssetValue;
        address[] memory positionAssets = Position(position).getPositionAssets();
        uint256[] memory positionAssetData = new uint256[](positionAssets.length);

        for (uint256 i; i < positionAssets.length; ++i) {
            uint256 assets = getAssetValue(position, positionAssets[i]);
            // positionAssetData[i] stores value of positionAssets[i] in eth
            positionAssetData[i] = assets;
            totalAssetValue += assets;
        }

        for (uint256 i; i < positionAssetData.length; ++i) {
            // positionAssetData[i] stores weight of positionAsset[i]
            // wt of positionAsset[i] = (value of positionAsset[i]) / (total position assets value)
            positionAssetData[i] = positionAssetData[i].mulDiv(1e18, totalAssetValue);
        }

        return (totalAssetValue, positionAssets, positionAssetData);
    }

    function _getCompositeLtvForPool(
        uint256[] memory debtPools,
        address[] memory positionAssets,
        uint256[] memory positionAssetWeight
    ) internal view returns (uint256[] memory) {
        uint256[] memory compositeLtvForPool = new uint256[](debtPools.length);

        // this nested loop is O(MAX_ASSETS * MAX_DEBT_POOLS) instead of the unbounded O(n^2)
        for (uint256 i; i < debtPools.length; ++i) {
            uint256 compositeLtv;
            for (uint256 j; j < positionAssets.length; ++j) {
                // ltv for given pool-asset pair
                uint256 ltv = riskEngine.ltvFor(debtPools[i], positionAssets[j]);
                // the intermediate value has 36 decimals
                // this will not overflow uint256 due to MAX_ASSETS and MAX_DEBT_POOLS
                compositeLtv += positionAssetWeight[j] * ltv;
            }

            // scale down the intermediate value to 18 decimals
            compositeLtvForPool[i] = compositeLtv / 1e18;
        }

        return compositeLtvForPool;
    }

    function _getMinReqAssetValue(uint256[] memory debtValueForPool, uint256[] memory compositeLtvForPool)
        internal
        pure
        returns (uint256)
    {
        uint256 minReqAssetValue;

        for (uint256 i; i < debtValueForPool.length; ++i) {
            minReqAssetValue += debtValueForPool[i].mulDiv(1e18, compositeLtvForPool[i], Math.Rounding.Ceil);
        }

        return minReqAssetValue;
    }
}
