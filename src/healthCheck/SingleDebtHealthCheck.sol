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
import {IHealthCheck} from "../interfaces/IHealthCheck.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// libraries
import {Errors} from "../lib/Errors.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/*//////////////////////////////////////////////////////////////
                    SingleDebtHealthCheck
//////////////////////////////////////////////////////////////*/

// TYPE == 0x1
contract SingleDebtHealthCheck is IHealthCheck {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    // the position type that this health check corresponds to
    uint256 public constant TYPE = 0x1;

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

    /// @notice check if a given position violates the risk thresholds
    function isPositionHealthy(address position) external view returns (bool) {
        assert(TYPE == IPosition(position).TYPE());
        // fetch the debt asset
        // since single debt positions can only have one debt asset
        // only read the first element of the array and ignore the rest
        address pool = IPosition(position).getDebtPools()[0];

        // there is no debt pool and therefore no debt
        if (pool == address(0)) {
            return true;
        }

        // fetch list of assets for given position
        address[] memory assets = IPosition(position).getAssets();

        // container array used to store additional info for each asset in the position
        uint256[] memory assetData = new uint256[](assets.length);

        // total asset balance in the position, denominated in eth with 18 decimals
        uint256 totalBalanceInWei;

        // loop over each collateral asset
        for (uint256 i; i < assets.length; ++i) {
            // compute eth value of collateral, scaled by 18 decimals
            // since there is only one debt pool, all assets are priced using oracles from that pool
            // the oracles are set by the pool manager and are specific to the given pool
            uint256 balanceInWei = getCollatValueInWei(pool, assets[i], IERC20(assets[i]).balanceOf(position));

            // assetData[i] stores the value collateral asset[i] in eth, scaled by 18 decimals
            assetData[i] = balanceInWei;

            // add current balance value to aggregate balance value
            totalBalanceInWei += balanceInWei;
        }

        // loop over assets to compute fraction of total balance held in each asset
        for (uint256 i; i < assets.length; ++i) {
            // assetData[i] stores fraction of total account balance held in asset[i]
            assetData[i] = assetData[i].mulDiv(1e18, totalBalanceInWei, Math.Rounding.Floor);
        }

        // compute aggregate position debt, since single debt position has only one debt pool this
        // value is equal to the borrows owed to that pool. the debt is converted to eth with 18 decimals
        // borrows = pool debt * price of borrow asset / eth
        // pool debt is denominated in notional debt asset terms
        // price of borrow asset / eth is fetched using the oracle associated with the same pool
        uint256 totalBorrowsInWei = getDebtValueInWei(pool, Pool(pool).asset(), Pool(pool).getBorrowsOf(position));

        // min account balance required in eth to meet risk threshold, scaled by 18 decimals
        uint256 minReqBalanceInWei;

        // calculating the min balance is non-trivial because while the position borrows from a
        // single pool, it uses multiple assets to collateralize the debt and the pool could have
        // different ltvs for each asset held by the position. we take a weighted average approach
        // where debt is weighted in proportion to the value of each asset in the position
        // loop over position assets
        for (uint256 i; i < assets.length; ++i) {
            // min balance = SUM (total borrows * asset[i].weight / asset[i].ltv)
            // total borrows are denominated in eth, scaled by 18 decimals
            // asset[i].weight is the fraction of total account balance held in asset[i]
            // asset[i].ltv is the ltv for asset[i] according to the only debt pool for the position
            minReqBalanceInWei +=
                totalBorrowsInWei.mulDiv(assetData[i], riskEngine.ltvFor(pool, assets[i]), Math.Rounding.Ceil);
        }

        // the position is healthy if the value of the assets in the position is more than the
        // minimum collateral required to meet the ltv requirements of debts from all pools
        // this reverts if borrows > balance, which is intended to never allow that
        return totalBalanceInWei - totalBorrowsInWei >= minReqBalanceInWei;
    }

    function isValidLiquidation(
        address position,
        DebtData[] calldata debt,
        AssetData[] calldata collat,
        uint256 liquidationDiscount
    ) external view returns (bool) {
        // compute the amount of debt repaid in wei. since there is only one debt pool, debt[]
        // need not have more than one element. we ignore everything other than the first element.
        uint256 debtInWei = getDebtValueInWei(debt[0].pool, debt[0].asset, debt[0].amt);
        uint256 totalDebtInWei =
            getDebtValueInWei(debt[0].pool, debt[0].asset, Pool(debt[0].pool).getBorrowsOf(position));

        if (debtInWei > totalDebtInWei.mulDiv(riskEngine.closeFactor(), 1e18)) revert Errors.RepaidTooMuchDebt();

        // fetch the debt pool. since single debt positions can only have one debt pool, only read
        // the first element of the array and ignore the rest
        address pool = IPosition(position).getDebtPools()[0];

        // compute the amount of collat requested by the liquidator in wei.
        uint256 collatInWei;
        for (uint256 i; i < collat.length; ++i) {
            collatInWei += getCollatValueInWei(pool, collat[i].asset, collat[i].amt);
        }

        if (collatInWei > debtInWei.mulDiv((1e18 + liquidationDiscount), 1e18)) revert Errors.SeizedTooMuchCollateral();

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            Internal View
    //////////////////////////////////////////////////////////////*/

    function getDebtValueInWei(address pool, address asset, uint256 amt) internal view returns (uint256) {
        return IOracle(riskEngine.oracleFor(pool, asset)).getValueInEth(asset, amt);
    }

    function getCollatValueInWei(address pool, address asset, uint256 amt) internal view returns (uint256) {
        return IOracle(riskEngine.oracleFor(pool, asset)).getValueInEth(asset, amt);
    }
}
