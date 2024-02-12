// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {Pool} from "../Pool.sol";
import {RiskEngine} from "../RiskEngine.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IPosition} from "../interfaces/IPosition.sol";
import {DebtData, AssetData} from "../PositionManager.sol";
import {IHealthCheck} from "../interfaces/IHealthCheck.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// TYPE == 0x2
contract SingleCollatHealthCheck is IHealthCheck {
    using Math for uint256;

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
        // fetch list of pools with active borrows for the given position
        address[] memory debtPools = IPosition(position).getDebtPools();

        // container array used to store additional info for each debt pool
        uint256[] memory debtInfo = new uint256[](debtPools.length);

        // fetch collateral asset for the position using getAsset()
        // since single collateral positions can only have one collateral asset
        // only read the first element of the array and ignore the rest
        address collateralAsset = IPosition(position).getAssets()[0];

        // total debt accrued by account, denominated in eth, with 18 decimals
        uint256 totalDebtInWei;

        // minimum position balance required to meet risk threshold denominated in eth, with 18 decimals
        uint256 minReqBalanceInWei;

        // loop over all debt pools and compute the aggrgate debt owed by the position, in eth terms
        // and the minimum balance, in eth terms, required to meet the risk threshold for that debt
        for (uint256 i; i < debtPools.length; ++i) {
            // fetch debt owed to debtPools[i] in eth, with 18 decimals
            // the oracle for the debt asset is pool-specific and is configured by the pool manager
            uint256 debtInWei =
                getDebtValueInWei(debtPools[i], Pool(debtPools[i]).asset(), Pool(debtPools[i]).getBorrowsOf(position));

            // add current pool debt to aggregate position debt
            totalDebtInWei += debtInWei;

            // min balance required in eth to meet risk threshold, scaled by 18 decimals
            // the ltv of the collateral asset is pool-specifc and is configured by th pool manager
            // min collateralAsset amt to back debt = debt owed / ltv for collateralAsset
            minReqBalanceInWei +=
                debtInWei.mulDiv(1e18, riskEngine.ltvFor(debtPools[i], collateralAsset), Math.Rounding.Ceil);

            // debtInfo[i] stores the debt owed by this position to debtPools[i], to be used later
            // debt is denominated in eth, with 18 decimals
            debtInfo[i] = debtInWei;
        }

        // loop over debtPools to compute the fraction of total debt owed to each pool
        for (uint256 i; i < debtPools.length; ++i) {
            // debtInfo[i] stores the fraction of total debt owed to debtPools[i], with 18 decimals
            // fraction = debt owed to pool[i] / total debt
            debtInfo[i] = debtInfo[i].mulDiv(1e18, totalDebtInWei, Math.Rounding.Ceil);
        }

        // total position balance, in terms of the collateral asset
        // since this position can only have a single collateral, it's balance is the total balance
        uint256 notionalBalance = IERC20(collateralAsset).balanceOf(position);

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
            totalBalanceInWei += IOracle(riskEngine.oracleFor(debtPools[i], collateralAsset)).getValueInEth(
                collateralAsset, notionalBalance
            ).mulDiv(debtInfo[i], 1e18);
        }

        // the position is healthy if the value of the assets in the position is more than the
        // minimum balance required to meet the ltv requirements of debts from all pools
        return totalBalanceInWei > minReqBalanceInWei;
    }

    function isValidLiquidation(
        address position,
        DebtData[] calldata debt,
        AssetData[] calldata collat,
        uint256 liquidationDiscount
    ) external view returns (bool) {
        // compute the total amount of debt repaid by the liquidator in wei
        uint256 debtInWei;
        for (uint256 i; i < debt.length; ++i) {
            debtInWei += getDebtValueInWei(debt[0].pool, debt[i].asset, debt[i].amt);
        }

        uint256 collatInWei;
        for (uint256 i; i < collat.length; ++i) {
            collatInWei += getCollateralValueInWei(position, collat[i].asset, collat[i].amt);
        }

        // TODO add custom error
        if (collatInWei > debtInWei.mulDiv((1e18 + liquidationDiscount), 1e18)) revert();

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            Internal View
    //////////////////////////////////////////////////////////////*/

    function getDebtValueInWei(address pool, address asset, uint256 amt) internal view returns (uint256) {
        return IOracle(riskEngine.oracleFor(pool, asset)).getValueInEth(asset, amt);
    }

    function getCollateralValueInWei(address position, address asset, uint256 amt) internal view returns (uint256) {
        address[] memory debtPools = IPosition(position).getDebtPools();
        uint256[] memory debtInfo = new uint256[](debtPools.length);

        uint256 totalDebt;
        for (uint256 i; i < debtPools.length; ++i) {
            uint256 debt = Pool(debtPools[i]).getBorrowsOf(position);
            totalDebt += debt;
            debtInfo[i] = debt;
        }
        for (uint256 i; i < debtPools.length; ++i) {
            debtInfo[i] = debtInfo[i].mulDiv(1e18, totalDebt);
        }

        uint256 collateralValue;
        for (uint256 i; i < debtPools.length; ++i) {
            collateralValue +=
                IOracle(riskEngine.oracleFor(debtPools[i], asset)).getValueInEth(asset, amt).mulDiv(debtInfo[i], 1e18);
        }

        return collateralValue;
    }
}
