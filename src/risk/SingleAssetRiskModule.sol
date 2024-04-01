// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import {Pool} from "../Pool.sol";
import {RiskEngine} from "../RiskEngine.sol";
import {IOracle} from "../interface/IOracle.sol";
import {IPosition} from "../interface/IPosition.sol";
import {DebtData, AssetData} from "../PositionManager.sol";
import {IRiskModule} from "../interface/IRiskModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// libraries
import {Errors} from "../lib/Errors.sol";
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

    // address of the risk engine to be associated with this health check
    // used to fetch oracles and ltvs for pools
    RiskEngine public immutable riskEngine;

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor(address _riskEngine) {
        riskEngine = RiskEngine(_riskEngine);
    }

    /*//////////////////////////////////////////////////////////////
                             Public View
    //////////////////////////////////////////////////////////////*/

    function isPositionHealthy(address position) external view returns (bool) {
        (uint256 totalAssetsInEth,, uint256 minReqAssetsInEth) = getRiskData(position);
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

        if (assetsSeizedInEth > debtRepaidInEth.mulDiv((1e18 + liquidationDiscount), 1e18)) {
            revert Errors.SeizedTooMuchCollateral();
        }

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                             Public View
    //////////////////////////////////////////////////////////////*/

    function getDebtValue(address pool, address asset, uint256 amt) public view returns (uint256) {
        address oracle = riskEngine.oracleFor(pool, asset);
        if (oracle == address(0)) revert Errors.NoOracleFound();
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
        for (uint256 i; i < debtPools.length; ++i) {
            debtInfo[i] = debtInfo[i].mulDiv(1e18, totalDebt);
        }

        uint256 assetValue;
        for (uint256 i; i < debtPools.length; ++i) {
            address oracle = riskEngine.oracleFor(debtPools[i], asset);
            if (oracle == address(0)) revert Errors.NoOracleFound();
            assetValue += IOracle(oracle).getValueInEth(asset, amt).mulDiv(debtInfo[i], 1e18);
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
                address oracle = riskEngine.oracleFor(debtPools[i], positionAsset);
                if (oracle == address(0)) revert Errors.NoOracleFound();

                // collateral value = weight * total notional collateral price of collateral
                // weight = fraction of the total debt owed to the given pool
                // total notional collateral is denominated in terms of the collateral asset of the position
                // the value of collateral is fetched using the given pool's oracle for collateralAsset
                // this oracle is set by the pool manager and can be different for different pools
                uint256 wt = debtInfo[i].mulDiv(1e18, totalDebtInEth, Math.Rounding.Ceil);
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
