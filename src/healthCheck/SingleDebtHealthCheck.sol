// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPool} from "../interfaces/IPool.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IPosition} from "../interfaces/IPosition.sol";
import {IRiskEngine} from "../interfaces/IRiskEngine.sol";
import {IHealthCheck} from "../interfaces/IHealthCheck.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// TYPE == 0x1
contract SingleDebtHealthCheck is IHealthCheck {
    using Math for uint256;

    IRiskEngine public riskEngine;

    function isPositionHealthy(address position) external returns (bool) {
        address pool = IPosition(position).getDebtPools()[0];

        address[] memory assets = IPosition(position).getAssets();
        uint256[] memory assetData = new uint256[](assets.length);

        uint256 totalBalanceInWei = 0;
        for (uint256 i; i < assets.length; ++i) {
            uint256 bal = IOracle(riskEngine.oracleFor(pool, assets[i])).getValueInEth(
                assets[i], IERC20(assets[i]).balanceOf(position)
            );
            assetData[i] = bal; // assetData[i] -> position balance of asset[i] in wei
            totalBalanceInWei += bal;
        }

        for (uint256 i; i < assets.length; ++i) {
            assetData[i] = assetData[i].mulDiv(1e18, totalBalanceInWei, Math.Rounding.Floor);
            // assetData[i] -> fraction of total account balance in asset[i]
        }

        address borrowAsset = IPool(pool).asset();
        uint256 totalBorrowsInWei = IOracle(riskEngine.oracleFor(pool, borrowAsset)).getValueInEth(
            borrowAsset, IPool(pool).getBorrowsOf(position)
        );

        uint256 minBalReqInWei = 0;
        for (uint256 i; i < assets.length; ++i) {
            minBalReqInWei +=
                totalBorrowsInWei.mulDiv(assetData[i], riskEngine.ltvFor(pool, assets[i]), Math.Rounding.Floor);
        }

        return totalBalanceInWei > minBalReqInWei;
    }
}
