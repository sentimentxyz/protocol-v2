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
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/*//////////////////////////////////////////////////////////////
                    Single Debt Risk Module
//////////////////////////////////////////////////////////////*/

// TYPE == 0x1
contract SingleDebtRiskModule is IRiskModule {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    // the position type that this health check corresponds to
    uint256 public constant TYPE = 0x1;

    // min debt in wei for single asset position types
    uint256 public immutable MIN_DEBT;

    // address of the risk engine to be associated with this health check
    // used to fetch oracles and ltvs for pools
    RiskEngine public immutable riskEngine;

    /*//////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/

    error SingleDebtRiskModule_DebtTooLow();
    error SingleDebtRiskModule_ZeroAssetsWithDebt();
    error SingleDebtRiskModule_InvalidDebtData();
    error SingleDebtRiskModule_SeizedTooMuch(uint256 seized, uint256 maxSeizedAmt);

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor(address _riskEngine, uint256 _minDebt) {
        riskEngine = RiskEngine(_riskEngine);
        MIN_DEBT = _minDebt;
    }

    /*//////////////////////////////////////////////////////////////
                            External View
    //////////////////////////////////////////////////////////////*/

    /// @notice check if a given position violates the risk thresholds
    function isPositionHealthy(address position) external view returns (bool) {
        (uint256 totalAssetsInEth, uint256 totalDebtInEth, uint256 minReqAssetsInEth) = getRiskData(position);

        // to allow efficient liquidations, revert if debt is less than min debt
        if (totalDebtInEth != 0 && totalDebtInEth < MIN_DEBT) revert SingleDebtRiskModule_DebtTooLow();

        // handle zero assets and non-zero debt edge case
        if (totalAssetsInEth == 0 && totalDebtInEth != 0) revert SingleDebtRiskModule_ZeroAssetsWithDebt();

        // the position is healthy if the value of the assets in the position is more than the
        // minimum collateral required to meet the ltv requirements of debts from all pools
        // this reverts if borrows > balance, which is intended to never allow that
        return totalAssetsInEth >= minReqAssetsInEth;
    }

    function isValidLiquidation(
        address position,
        DebtData[] calldata debt,
        AssetData[] calldata collat,
        uint256 liquidationDiscount
    ) external view returns (bool) {
        // assert that debt[] is a singleton array
        if (debt.length != 1 || debt[0].pool != IPosition(position).getDebtPools()[0]) {
            revert SingleDebtRiskModule_InvalidDebtData();
        }

        // compute the amount of debt repaid in wei. since there is only one debt pool, debt[]
        // need not have more than one element. we ignore everything other than the first element.
        uint256 debtInWei = getDebtValue(debt[0].pool, debt[0].asset, debt[0].amt);

        // fetch the debt pool. since single debt positions can only have one debt pool, only read
        // the first element of the array and ignore the rest
        address pool = IPosition(position).getDebtPools()[0];

        // compute the amount of collat requested by the liquidator in wei.
        uint256 collatInWei;
        for (uint256 i; i < collat.length; ++i) {
            collatInWei += getAssetValue(pool, collat[i].asset, collat[i].amt);
        }

        // [ROUND] liquidation discount is rounded down, in favor of the protocol
        uint256 maxSeizedAmt = debtInWei.mulDiv((1e18 + liquidationDiscount), 1e18);
        if (collatInWei > maxSeizedAmt) {
            revert SingleDebtRiskModule_SeizedTooMuch(collatInWei, maxSeizedAmt);
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

    function getTotalDebtValue(address position) public view returns (uint256) {
        address pool = _fetchDebtPoolOrZero(position);
        if (pool == address(0)) return 0;
        return getDebtValue(pool, Pool(pool).asset(), Pool(pool).getBorrowsOf(position));
    }

    function getAssetValue(address pool, address asset, uint256 amt) public view returns (uint256) {
        // will revert with RiskEngine_NoOracleFound if missing
        address oracle = riskEngine.getOracleFor(pool, asset);
        return IOracle(oracle).getValueInEth(asset, amt);
    }

    function getTotalAssetValue(address position) public view returns (uint256) {
        address pool = _fetchDebtPoolOrZero(position);

        if (pool == address(0)) return 0;

        address[] memory assets = IPosition(position).getAssets();

        uint256 totalAssetsInEth;

        for (uint256 i; i < assets.length; ++i) {
            uint256 assetValueInEth = getAssetValue(pool, assets[i], IERC20(assets[i]).balanceOf(position));
            totalAssetsInEth += assetValueInEth;
        }

        return totalAssetsInEth;
    }

    function getRiskData(address position) public view returns (uint256, uint256, uint256) {
        assert(TYPE == IPosition(position).TYPE());

        // fetch the debt asset or zero if there is no debt pool
        address pool = _fetchDebtPoolOrZero(position);

        // fetch total position debt, in eth
        uint256 totalDebtInEth;
        if (pool != address(0)) {
            // compute aggregate position debt, since single debt position has only one debt pool this
            // value is equal to the borrows owed to that pool. the debt is converted to eth with 18 decimals
            // borrows = pool debt * price of borrow asset / eth
            // pool debt is denominated in notional debt asset terms
            // price of borrow asset / eth is fetched using the oracle associated with the same pool
            totalDebtInEth = getDebtValue(pool, Pool(pool).asset(), Pool(pool).getBorrowsOf(position));
        }

        // fetch list of position assets
        address[] memory assets = IPosition(position).getAssets();

        // total asset balance in the position, denominated in eth with 18 decimals
        uint256 totalAssetsInEth;

        // min account balance required in eth to meet risk threshold, scaled by 18 decimals
        uint256 minReqAssetsInEth;

        if (assets.length != 0 && pool != address(0)) {
            // container array used to store additional info for each asset in the position
            uint256[] memory assetData = new uint256[](assets.length);

            // loop over each collateral asset
            for (uint256 i; i < assets.length; ++i) {
                // compute eth value of collateral, scaled by 18 decimals
                // since there is only one debt pool, all assets are priced using oracles from that pool
                // the oracles are set by the pool manager and are specific to the given pool
                assetData[i] = getAssetValue(pool, assets[i], IERC20(assets[i]).balanceOf(position));

                // update total assets with amount of assets[i]
                totalAssetsInEth += assetData[i];
            }

            // loop over assets to compute fraction of total balance held in each asset to calculate
            // the minimum assets required in eth terms to stay within position health thresholds
            // calculating the min balance is non-trivial because while the position borrows from a
            // single pool, it uses multiple assets to collateralize the debt and the pool could have
            // different ltvs for each asset held by the position. we take a weighted average approach
            // where debt is weighted in proportion to the value of each asset in the position
            // loop over position assets
            for (uint256 i; i < assets.length; ++i) {
                // min balance = SUM (total borrows * wt / asset[i].ltv)
                // total borrows are denominated in eth, scaled by 18 decimals
                // wt is the fraction of total account balance held in asset[i]
                // asset[i].ltv is the ltv for asset[i] according to the only debt pool for the position
                // [ROUND] asset weights are rounded down so that SUM(assetData[i]) < 1
                uint256 wt = assetData[i].mulDiv(1e18, totalAssetsInEth, Math.Rounding.Floor);

                // [ROUND] minimum assets required is rounded up, in favor of the protocol
                minReqAssetsInEth += totalDebtInEth.mulDiv(wt, riskEngine.ltvFor(pool, assets[i]), Math.Rounding.Ceil);
            }
        }

        return (totalAssetsInEth, totalDebtInEth, minReqAssetsInEth);
    }

    /*//////////////////////////////////////////////////////////////
                            Internal View
    //////////////////////////////////////////////////////////////*/

    function _fetchDebtPoolOrZero(address position) internal view returns (address) {
        // fetch list of pools with active borrows for the given position
        address[] memory debtPools = IPosition(position).getDebtPools();

        // return position debt pool, or zero address if there is no debt pool
        return (debtPools.length == 0) ? address(0) : debtPools[0];
    }
}
