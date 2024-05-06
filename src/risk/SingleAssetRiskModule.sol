// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import {Pool} from "../Pool.sol";
import {RiskEngine} from "../RiskEngine.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IPosition} from "../interfaces/IPosition.sol";
import {DebtData, AssetData} from "../PositionManager.sol";
import {IRiskModule} from "../interfaces/IRiskModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// libraries
import {IterableSet} from "../lib/IterableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/*//////////////////////////////////////////////////////////////
                    Single Asset Risk Module
//////////////////////////////////////////////////////////////*/

// TYPE == 0x2
contract SingleAssetRiskModule is IRiskModule {
    using Math for uint256;
    using IterableSet for IterableSet.IterableSetStorage;

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    // the position type that this health check corresponds to
    uint256 public constant TYPE = 0x2;

    // min debt in wei for single asset position types
    uint256 public immutable MIN_DEBT;

    // address of the risk engine to be associated with this health check
    // used to fetch oracles and ltvs for pools
    RiskEngine public immutable riskEngine;

    /*//////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/

    error SingleAssetRiskModule_DebtTooLow();
    error SingleAssetRiskModule_InvalidDebtData();
    error SingleAssetRiskModule_ZeroAssetsWithDebt();
    error SingleAssetRiskModule_SeizedTooMuch(uint256 seized, uint256 maxSeizedAmt);

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor(address _riskEngine, uint256 _minDebt) {
        riskEngine = RiskEngine(_riskEngine);
        MIN_DEBT = _minDebt;
    }

    /*//////////////////////////////////////////////////////////////
                             Public View
    //////////////////////////////////////////////////////////////*/

    function isPositionHealthy(address position) external view returns (bool) {
        (uint256 totalAssetsInEth, uint256 totalDebtInEth, uint256 minReqAssetsInEth) = getRiskData(position);

        // to allow efficient liquidations, revert if debt is less than min debt
        if (totalDebtInEth != 0 && totalDebtInEth < MIN_DEBT) revert SingleAssetRiskModule_DebtTooLow();

        // handle zero assets and non-zero debt edge case
        if (totalAssetsInEth == 0 && totalDebtInEth != 0) revert SingleAssetRiskModule_ZeroAssetsWithDebt();

        // the position is healthy if the value of the assets in the position is more than the
        // minimum balance required to meet the ltv requirements of debts from all pools
        return totalAssetsInEth >= minReqAssetsInEth;
    }

    function isValidLiquidation(
        address position,
        DebtData[] calldata debt,
        AssetData[] calldata collat,
        uint256 liquidationDiscount
    ) external view returns (bool) {
        // compute the total amount of debt repaid by the liquidator in wei
        uint256 debtRepaidInEth;
        for (uint256 i; i < debt.length; ++i) {
            debtRepaidInEth += getDebtValue(debt[0].pool, debt[i].asset, debt[i].amt);
        }

        uint256 assetsSeizedInEth;
        for (uint256 i; i < collat.length; ++i) {
            assetsSeizedInEth += getAssetValue(position, collat[i].asset, collat[i].amt);
        }

        // [ROUND] liquidation discount is rounded down, in favor of the protocol
        uint256 maxAmtSeized = debtRepaidInEth.mulDiv((1e18 + liquidationDiscount), 1e18);
        if (assetsSeizedInEth > maxAmtSeized) {
            revert SingleAssetRiskModule_SeizedTooMuch(assetsSeizedInEth, maxAmtSeized);
        }

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                             Public View
    //////////////////////////////////////////////////////////////*/

    function getDebtValue(address pool, address asset, uint256 amt) public view returns (uint256) {
        // will revert with RiskEngine_NoOracleFound if missing
        address oracle = riskEngine.getOracleFor(pool, asset);
        return IOracle(oracle).getValueInEth(asset, amt);
    }

    // no need to explicitly handle zero debt positions, this returns zero in that case
    function getTotalDebtValue(address position) public view returns (uint256) {
        address[] memory debtPools = IPosition(position).getDebtPools();
        uint256 totalDebtInEth;
        for (uint256 i; i < debtPools.length; ++i) {
            totalDebtInEth +=
                getDebtValue(debtPools[i], Pool(debtPools[i]).asset(), Pool(debtPools[i]).getBorrowsOf(position));
        }
        return totalDebtInEth;
    }

    // no need to explicitly handle zero debt positions, this returns zero in that case
    function getAssetValue(address position, address asset, uint256 amt) public view returns (uint256) {
        address[] memory debtPools = IPosition(position).getDebtPools();
        uint256[] memory debtInfo = new uint256[](debtPools.length);

        uint256 totalDebt; // in notional units
        for (uint256 i; i < debtPools.length; ++i) {
            uint256 debt = Pool(debtPools[i]).getBorrowsOf(position);
            totalDebt += debt;
            debtInfo[i] = debt;
        }

        // [ROUND] debt weights are rounded up, to enforce a hard cap on the amount seized
        for (uint256 i; i < debtPools.length; ++i) {
            debtInfo[i] = debtInfo[i].mulDiv(1e18, totalDebt, Math.Rounding.Ceil);
        }

        uint256 assetValue;
        for (uint256 i; i < debtPools.length; ++i) {
            // will revert with RiskEngine_NoOracleFound if missing
            address oracle = riskEngine.getOracleFor(debtPools[i], asset);

            // [ROUND] asset values are rounded up, to enforce a hard cap on the amount seized
            assetValue += IOracle(oracle).getValueInEth(asset, amt).mulDiv(debtInfo[i], 1e18, Math.Rounding.Ceil);
        }

        return assetValue;
    }

    // no need to explicitly handle zero debt positions, this returns zero in that case
    function getTotalAssetValue(address position) public view returns (uint256) {
        address asset = _fetchAssetOrZero(position);
        if (asset == address(0)) return 0;
        return getAssetValue(position, asset, IERC20(asset).balanceOf(position));
    }

    function getRiskData(address position) public view returns (uint256, uint256, uint256) {
        assert(TYPE == IPosition(position).TYPE());

        // total debt accrued by account, denominated in eth, with 18 decimals
        uint256 totalDebtInEth;

        // fetch list of pools with active borrows for the given position
        address[] memory debtPools = IPosition(position).getDebtPools();

        // container array used to store additional info for each debt pool
        uint256[] memory debtInfo = new uint256[](debtPools.length);

        // a position with no debt has zero value in assets, debt and min req assets
        // since there are no associated oracles that can be used to value these
        // if (debtPools.length == 0) return (0, 0, 0);
        if (debtPools.length != 0) {
            for (uint256 i; i < debtPools.length; ++i) {
                uint256 debtInWei =
                    getDebtValue(debtPools[i], Pool(debtPools[i]).asset(), Pool(debtPools[i]).getBorrowsOf(position));

                // add current pool debt to aggregate position debt
                totalDebtInEth += debtInWei;

                // debtInfo[i] stores the debt owed by this position to debtPools[i], to be used later
                // debt is denominated in eth, with 18 decimals
                debtInfo[i] = debtInWei;
            }
        }

        // minimum position balance required to meet risk threshold denominated in eth, with 18 decimals
        uint256 minReqAssetsInEth;

        // total position balance in eth, with 18 decimals
        uint256 totalBalanceInWei;

        // fetch collateral asset for the position using getAsset()
        address positionAsset = _fetchAssetOrZero(position);

        if (positionAsset != address(0) && debtPools.length != 0) {
            // loop over all debt pools and compute the aggrgate debt owed by the position, in eth terms
            // and the minimum balance, in eth terms, required to meet the risk threshold for that debt
            for (uint256 i; i < debtPools.length; ++i) {
                // [ROUND] minimum assets required is rounded up, in favor of the protocol
                minReqAssetsInEth +=
                    debtInfo[i].mulDiv(1e18, riskEngine.ltvFor(debtPools[i], positionAsset), Math.Rounding.Ceil);
            }

            // total position balance, in terms of the collateral asset
            // since this position can only have a single collateral, it's balance is the total balance
            uint256 notionalBalance = IERC20(positionAsset).balanceOf(position);

            // pricing the collateral is non-trivial since every debt pool has a different oracle
            // it is priced as a weighted average of all debt pool prices
            // the weight of each pool is the fraction of total debt owed to that pool
            // loop over debt pools to compute total position balance using debt pool weighted prices
            for (uint256 i; i < debtPools.length; ++i) {
                // fetch oracle associated with the position asset for debtPools[i]
                // will revert with RiskEngine_NoOracleFound if missing
                address oracle = riskEngine.getOracleFor(debtPools[i], positionAsset);

                // collateral value = weight * total notional collateral price of collateral
                // weight = fraction of the total debt owed to the given pool
                // total notional collateral is denominated in terms of the collateral asset of the position
                // the value of collateral is fetched using the given pool's oracle for collateralAsset
                // this oracle is set by the pool manager and can be different for different pools
                // [ROUND] debt weights are rounded down, so that SUM(debtInfo[i]) < 1
                uint256 wt = debtInfo[i].mulDiv(1e18, totalDebtInEth);

                // [ROUND] total balance is scaled down, in favor of the protocol
                totalBalanceInWei += IOracle(oracle).getValueInEth(positionAsset, notionalBalance).mulDiv(wt, 1e18);
            }
        }

        return (totalBalanceInWei, totalDebtInEth, minReqAssetsInEth);
    }

    /*//////////////////////////////////////////////////////////////
                            Internal VIew
    //////////////////////////////////////////////////////////////*/

    function _fetchAssetOrZero(address position) internal view returns (address) {
        address[] memory assets = IPosition(position).getAssets();

        return (assets.length == 0) ? address(0) : assets[0];
    }
}
