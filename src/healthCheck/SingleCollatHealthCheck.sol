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
                    SingleCollatHealthCheck
//////////////////////////////////////////////////////////////*/

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
        assert(TYPE == IPosition(position).TYPE());
        // fetch list of pools with active borrows for the given position
        address[] memory debtPools = IPosition(position).getDebtPools();

        // if there are no debt pools and therefore no debt
        if (debtPools.length == 0) {
            return true;
        }

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
            uint256 debtInWei = debtValue(debtPools[i], position);

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
        // loop over debt pools
        for (uint256 i; i < debtPools.length; ++i) {
            // compute total position balance using debt pool weighted prices
            totalBalanceInWei += collateralValue(debtPools[i], collateralAsset, notionalBalance, debtInfo[i]);
        }

        // the position is healthy if the value of the assets in the position is more than the
        // minimum balance required to meet the ltv requirements of debts from all pools
        return totalBalanceInWei > minReqBalanceInWei;
    }

    /*//////////////////////////////////////////////////////////////
                            Internal View
    //////////////////////////////////////////////////////////////*/

    /// @notice The debt value of position according to the pools oracle
    function debtValue(address pool, address position) internal view returns (uint256) {
        // debt = notional debt * eth price of debt asset
        // notional debt is denominated in the debt assets
        // the value of debt in eth is fetched from the associated oracle for the given pool
        // this oracle is set by the pool manager in RiskEngine and can be diff for diff pools
        return IOracle(riskEngine.oracleFor(pool, Pool(pool).asset())).getValueInEth(
            Pool(pool).asset(), Pool(pool).getBorrowsOf(position)
        );
    }

    /// @notice fetch weighted collateral value for a given asset using a particular pool's oracle
    function collateralValue(address pool, address asset, uint256 amt, uint256 wt) internal view returns (uint256) {
        // collateral value = weight * total notional collateral price of collateral
        // weight = fraction of the total debt owed to the given pool
        // total notional collateral is denominated in terms of the collateral asset of the position
        // the value of collateral is fetched using the given pool's oracle for collateralAsset
        // this oracle is set by the pool manager and can be different for different pools
        return
            IOracle(riskEngine.oracleFor(pool, asset)).getValueInEth(asset, amt.mulDiv(wt, 1e18, Math.Rounding.Floor));
    }
}
