// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPool} from "../interfaces/IPool.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IPosition} from "../interfaces/IPosition.sol";
import {IRiskEngine} from "../interfaces/IRiskEngine.sol";
import {IHealthCheck} from "../interfaces/IHealthCheck.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// TYPE == 0x2
contract SingleCollatHealthCheck is IHealthCheck {
    using Math for uint256;

    IRiskEngine public riskEngine;

    function isPositionHealthy(address position) external view returns (bool) {
        address[] memory debtPools = IPosition(position).getDebtPools();
        uint256[] memory debtInfo = new uint256[](debtPools.length);

        address collateralAsset = IPosition(position).getAssets()[0];
        uint256 totalDebtInWei;
        uint256 minReqBalanceInWei;

        for (uint256 i; i < debtPools.length; ++i) {
            uint256 debtInWei = IOracle(riskEngine.oracleFor(debtPools[i], IPool(debtPools[i]).asset())).getValueInEth(
                IPool(debtPools[i]).asset(), IPool(debtPools[i]).getBorrowsOf(position)
            );
            totalDebtInWei += debtInWei;
            minReqBalanceInWei +=
                debtInWei.mulDiv(1e18, riskEngine.ltvFor(debtPools[i], collateralAsset), Math.Rounding.Ceil);
            debtInfo[i] = debtInWei; // debtInfo[i] -> position debt in eth owed to debtPools[i]
        }

        for (uint256 i; i < debtPools.length; ++i) {
            debtInfo[i] = debtInfo[i].mulDiv(1e18, totalDebtInWei, Math.Rounding.Ceil);
            // debtInfo[i] -> fraction of total debt owed to debtPools[i]
        }

        uint256 notionalBal = IERC20(collateralAsset).balanceOf(position);
        uint256 totalBalanceInWei;
        for (uint256 i; i < debtPools.length; ++i) {
            totalBalanceInWei += IOracle(riskEngine.oracleFor(debtPools[i], collateralAsset)).getValueInEth(
                collateralAsset, notionalBal.mulDiv(debtInfo[i], 1e18, Math.Rounding.Floor)
            );
        }

        return totalBalanceInWei > minReqBalanceInWei;
    }
}
