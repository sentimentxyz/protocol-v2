// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Pool} from "../Pool.sol";
import {RiskEngine} from "../RiskEngine.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IPosition} from "../interfaces/IPosition.sol";
import {IHealthCheck} from "../interfaces/IHealthCheck.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// TYPE == 0x2
contract SingleCollatHealthCheck is IHealthCheck {
    using Math for uint256;

    uint256 public constant TYPE = 2;

    RiskEngine public riskEngine;

    function isPositionHealthy(address position) external view returns (bool) {
        address[] memory debtPools = IPosition(position).getDebtPools();
        uint256[] memory debtInfo = new uint256[](debtPools.length);

        address collateralAsset = IPosition(position).getAssets()[0];
        uint256 totalDebtInWei;
        uint256 minReqBalanceInWei;

        for (uint256 i; i < debtPools.length; ++i) {
            uint256 debtInWei = debtValue(debtPools[i], position);

            totalDebtInWei += debtInWei;
            minReqBalanceInWei +=
                debtInWei.mulDiv(1e18, riskEngine.ltvFor(debtPools[i], collateralAsset), Math.Rounding.Ceil);

            // debtInfo[i] -> position debt in eth owed to debtPools[i]
            debtInfo[i] = debtInWei; 
        }

        for (uint256 i; i < debtPools.length; ++i) {
            // debtInfo[i] -> fraction of total debt owed to debtPools[i]
            debtInfo[i] = debtInfo[i].mulDiv(1e18, totalDebtInWei, Math.Rounding.Ceil);
        }

        uint256 notionalBalance = IERC20(collateralAsset).balanceOf(position);
        uint256 totalBalanceInWei;
        for (uint256 i; i < debtPools.length; ++i) {
            totalBalanceInWei += collateralValue(debtPools[i], collateralAsset, notionalBalance, debtInfo[i]);
        }

        return totalBalanceInWei > minReqBalanceInWei;
    }

    /// @notice The debt value of position according to the pools oracle
    function debtValue(address pool, address position) internal view returns (uint256) {
        return IOracle(riskEngine.oracleFor(pool, Pool(pool).asset())).getValueInEth(
            Pool(pool).asset(), Pool(pool).getBorrowsOf(position)
        );
    }
    
    /// @notice The collateral value of wt * amt of asset according to the pools oracle
    /// @notice we break up the collateral into "virtual" positions according to the reported amount of debt
    /// @param wt weight of the asset in the pool
    function collateralValue(address pool, address asset, uint256 amt, uint256 wt) internal view returns (uint256) {
        return
            IOracle(riskEngine.oracleFor(pool, asset)).getValueInEth(asset, amt.mulDiv(wt, 1e18, Math.Rounding.Floor));
    }
}
