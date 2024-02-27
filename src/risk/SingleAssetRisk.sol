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
import {IHealthCheck} from "../interfaces/IHealthCheck.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// libraries
import {Errors} from "../lib/Errors.sol";
import {IterableSet} from "../lib/IterableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/*//////////////////////////////////////////////////////////////
                    SingleCollatHealthCheck
//////////////////////////////////////////////////////////////*/

// TYPE == 0x2
contract SingleAssetRisk is IRiskModule {
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
        // short circuit happy path with zero debt
        if (IPosition(position).getDebtPools().length == 0) return true;

        (uint256 totalAssetsInEth, uint256 totalDebtInEth, uint256 minReqAssetsInEth) = getRiskData(position);
        // the position is healthy if the value of the assets in the position is more than the
        // minimum balance required to meet the ltv requirements of debts from all pools
        return totalAssetsInEth - totalDebtInEth >= minReqAssetsInEth;
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

        if (debtRepaidInEth > getTotalDebtValue(position).mulDiv(riskEngine.closeFactor(), 1e18)) {
            revert Errors.RepaidTooMuchDebt();
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
                            Internal View
    //////////////////////////////////////////////////////////////*/

    function getDebtValue(address pool, address asset, uint256 amt) public view returns (uint256) {
        return IOracle(riskEngine.oracleFor(pool, asset)).getValueInEth(asset, amt);
    }

    function getTotalDebtValue(address position) public view returns (uint256) {
        address[] memory debtPools = IPosition(position).getDebtPools();
        uint256 totalDebtInEth;
        for (uint256 i; i < debtPools.length; ++i) {
            totalDebtInEth +=
                getDebtValue(debtPools[i], Pool(debtPools[i]).asset(), Pool(debtPools[i]).getBorrowsOf(position));
        }
        return totalDebtInEth;
    }

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
            assetValue +=
                IOracle(riskEngine.oracleFor(debtPools[i], asset)).getValueInEth(asset, amt).mulDiv(debtInfo[i], 1e18);
        }

        return assetValue;
    }

    function getTotalAssetValue(address position) external view returns (uint256) {
        address[] memory assets = IPosition(position).getAssets();
        if (assets.length == 0) return 0;
        return getAssetValue(position, assets[0], IERC20(assets[0]).balanceOf(position));
    }

    function getRiskData(address position) public view returns (uint256, uint256, uint256) {
        assert(TYPE == IPosition(position).TYPE());
        // fetch list of pools with active borrows for the given position
        address[] memory debtPools = IPosition(position).getDebtPools();

        // container array used to store additional info for each debt pool
        uint256[] memory debtInfo = new uint256[](debtPools.length);

        // fetch collateral asset for the position using getAsset()
        // since single collateral positions can only have one collateral asset
        // only read the first element of the array and ignore the rest
        address positionAsset = IPosition(position).getAssets()[0];

        // total debt accrued by account, denominated in eth, with 18 decimals
        uint256 totalDebtInEth;

        // minimum position balance required to meet risk threshold denominated in eth, with 18 decimals
        uint256 minReqAssetsInEth;

        // loop over all debt pools and compute the aggrgate debt owed by the position, in eth terms
        // and the minimum balance, in eth terms, required to meet the risk threshold for that debt
        for (uint256 i; i < debtPools.length; ++i) {
            // fetch debt owed to debtPools[i] in eth, with 18 decimals
            // the oracle for the debt asset is pool-specific and is configured by the pool manager
            uint256 debtInWei =
                getDebtValue(debtPools[i], Pool(debtPools[i]).asset(), Pool(debtPools[i]).getBorrowsOf(position));

            // add current pool debt to aggregate position debt
            totalDebtInEth += debtInWei;

            // min balance required in eth to meet risk threshold, scaled by 18 decimals
            // the ltv of the collateral asset is pool-specifc and is configured by th pool manager
            // min collateralAsset amt to back debt = debt owed / ltv for collateralAsset
            minReqAssetsInEth +=
                debtInWei.mulDiv(1e18, riskEngine.ltvFor(debtPools[i], positionAsset), Math.Rounding.Ceil);

            // debtInfo[i] stores the debt owed by this position to debtPools[i], to be used later
            // debt is denominated in eth, with 18 decimals
            debtInfo[i] = debtInWei;
        }

        // loop over debtPools to compute the fraction of total debt owed to each pool
        for (uint256 i; i < debtPools.length; ++i) {
            // debtInfo[i] stores the fraction of total debt owed to debtPools[i], with 18 decimals
            // fraction = debt owed to pool[i] / total debt
            debtInfo[i] = debtInfo[i].mulDiv(1e18, totalDebtInEth, Math.Rounding.Ceil);
        }

        // total position balance, in terms of the collateral asset
        // since this position can only have a single collateral, it's balance is the total balance
        uint256 notionalBalance = IERC20(positionAsset).balanceOf(position);

        // total position balance in eth, with 18 decimals
        uint256 totalBalanceInWei;

        // pricing the collateral is non-trivial since every debt pool has a different oracle
        // it is priced as a weighted average of all debt pool prices
        // the weight of each pool is the fraction of total debt owed to that pool
        // loop over debt pools to compute total position balance using debt pool weighted prices
        for (uint256 i; i < debtPools.length; ++i) {
            // collateral value = weight * total notional collateral price of collateral
            // weight = fraction of the total debt owed to the given pool
            // total notional collateral is denominated in terms of the collateral asset of the position
            // the value of collateral is fetched using the given pool's oracle for collateralAsset
            // this oracle is set by the pool manager and can be different for different pools
            totalBalanceInWei += IOracle(riskEngine.oracleFor(debtPools[i], positionAsset)).getValueInEth(
                positionAsset, notionalBalance
            ).mulDiv(debtInfo[i], 1e18);
        }

        return (totalBalanceInWei, totalDebtInEth, minReqAssetsInEth);
    }
}
