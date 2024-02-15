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
import {IHealthCheck} from "../interfaces/IHealthCheck.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// libraries
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

    /// @notice check if a given position violates
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
            uint256 balanceInWei = collateralValue(pool, position, assets[i]);

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

        address debtAsset = Pool(pool).asset();
        // compute aggregate position debt, since single debt position has only one debt pool this
        // value is equal to the borrows owed to that pool. the debt is converted to eth with 18 decimals
        // borrows = pool debt * price of borrow asset / eth
        // pool debt is denominated in notional debt asset terms
        // price of borrow asset / eth is fetched using the oracle associated with the same pool
        uint256 totalBorrowsInWei =
            IOracle(riskEngine.oracleFor(pool, debtAsset)).getValueInEth(debtAsset, Pool(pool).getBorrowsOf(position));

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
        // minimum balance required to meet the ltv requirements of debts from all pools
        return totalBalanceInWei > minReqBalanceInWei;
    }

    /*//////////////////////////////////////////////////////////////
                            Internal View
    //////////////////////////////////////////////////////////////*/

    /// @notice the value of asset of a position in eth according to the pools oracle
    function collateralValue(address pool, address position, address asset) internal view returns (uint256) {
        // collateral value = balanceOf[asset] * price[asset]
        // balance[asset] is the amount of asset held in the position, or the ERC20.balanceOf asset
        // price[asset] is the price of asset according to given pool's oracle
        return IOracle(riskEngine.oracleFor(pool, asset)).getValueInEth(asset, IERC20(asset).balanceOf(position));
    }
}
