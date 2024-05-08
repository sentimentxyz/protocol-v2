// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {Pool} from "./Pool.sol";
import {Position} from "./Position.sol";
import {RiskEngine} from "./RiskEngine.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {DebtData, AssetData} from "./PositionManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract RiskModule {
    using Math for uint256;

    uint256 public constant VERSION = 1;
    uint256 public immutable MIN_DEBT;
    RiskEngine public immutable RISK_ENGINE;
    uint256 public immutable LIQUIDATION_DISCOUNT;

    error RiskModule_DebtTooLow(address position);
    error RiskModule_ZeroAssetsWithDebt(address position);

    constructor(uint256 minDebt_, address riskEngine_, uint256 liquidationDiscount_) {
        MIN_DEBT = minDebt_;
        RISK_ENGINE = RiskEngine(riskEngine_);
        LIQUIDATION_DISCOUNT = liquidationDiscount_;
    }

    function isPositionHealthy(address position) external view returns (bool) {
        (uint256 totalAssetValue, uint256 totalDebtValue, uint256 minReqAssetValue) = getRiskData(position);

        if (totalDebtValue != 0 && totalDebtValue < MIN_DEBT) revert RiskModule_DebtTooLow(position);
        if (totalAssetValue == 0 && totalDebtValue != 0) revert RiskModule_ZeroAssetsWithDebt(position);

        return totalAssetValue >= minReqAssetValue;
    }

    function getRiskData(address position) public view returns (uint256, uint256, uint256) {
        (uint256 totalAssetValue, address[] memory positionAssets, uint256[] memory positionAssetWeight) =
            _getPositionAssetData(position);

        (uint256 totalDebtValue, address[] memory debtPools, uint256[] memory debtValueForPool) =
            _getPositionDebtData(position);

        if (totalDebtValue == 0) return (totalAssetValue, 0, 0);

        uint256[] memory compositeLtvForPool = _getCompositeLtvForPool(debtPools, positionAssets, positionAssetWeight);

        uint256 minReqAssetValue = _getMinReqAssetValue(debtValueForPool, compositeLtvForPool);

        return (totalAssetValue, totalDebtValue, minReqAssetValue);
    }

    function isValidLiquidation(address position, DebtData[] calldata debt, AssetData[] calldata assets)
        external
        view
        returns (bool)
    {}

    /*//////////////////////////////////////////////////////////////
                          Position Debt Math
    //////////////////////////////////////////////////////////////*/

    function getDebtValueForPool(address position, address debtPool) public view returns (uint256) {
        Pool pool = Pool(debtPool);
        address asset = pool.asset();
        IOracle oracle = IOracle(RISK_ENGINE.getOracleFor(asset));
        return oracle.getValueInEth(asset, pool.getBorrowsOf(position));
    }

    function getTotalDebtValue(address position) public view returns (uint256) {
        address[] memory debtPools = Position(position).getDebtPools();

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
        IOracle oracle = IOracle(RISK_ENGINE.getOracleFor(asset));
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
        returns (uint256, address[] memory, uint256[] memory)
    {
        uint256 totalDebtValue;
        address[] memory debtPools = Position(position).getDebtPools();
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
        address[] memory debtPools,
        address[] memory positionAssets,
        uint256[] memory positionAssetWeight
    ) internal view returns (uint256[] memory) {
        uint256[] memory compositeLtvForPool = new uint256[](debtPools.length);

        // this nested loop is O(MAX_ASSETS * MAX_DEBT_POOLS) instead of the unbounded O(n^2)
        for (uint256 i; i < debtPools.length; ++i) {
            uint256 compositeLtv;
            for (uint256 j; j < positionAssets.length; ++j) {
                // ltv for given pool-asset pair
                uint256 ltv = RISK_ENGINE.ltvFor(debtPools[i], positionAssets[j]);

                // the intermediate value has 36 decimals
                // this will not overflow uint256 due to MAX_ASSETS and MAX_DEBT_POOLS
                compositeLtv += positionAssetWeight[j] * ltv;
            }

            // scale down the intermediate value to 18 decimals
            compositeLtvForPool[i] = compositeLtv / (positionAssets.length * 1e18);
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
