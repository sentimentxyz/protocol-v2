// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Pool} from "../Pool.sol";
import {RiskEngine} from "../RiskEngine.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IPosition} from "../interfaces/IPosition.sol";
import {IHealthCheck} from "../interfaces/IHealthCheck.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// TYPE == 0x1
contract SingleDebtHealthCheck is IHealthCheck {
    using Math for uint256;

    RiskEngine public riskEngine;

    function isPositionHealthy(address position) external view returns (bool) {
        address pool = IPosition(position).getDebtPools()[0];

        address[] memory assets = IPosition(position).getAssets();
        uint256[] memory assetData = new uint256[](assets.length);

        uint256 totalBalanceInWei;
        for (uint256 i; i < assets.length; ++i) {
            uint256 balanceInWei = fetchBalanceInWei(pool, position, assets[i]);
            assetData[i] = balanceInWei; // assetData[i] -> position balance of asset[i] in wei
            totalBalanceInWei += balanceInWei;
        }

        for (uint256 i; i < assets.length; ++i) {
            assetData[i] = assetData[i].mulDiv(1e18, totalBalanceInWei, Math.Rounding.Floor);
            // assetData[i] -> fraction of total account balance in asset[i]
        }

        address borrowAsset = Pool(pool).asset();
        uint256 totalBorrowsInWei = IOracle(riskEngine.oracleFor(pool, borrowAsset)).getValueInEth(
            borrowAsset, Pool(pool).getBorrowsOf(position)
        );

        uint256 minReqBalanceInWei;
        for (uint256 i; i < assets.length; ++i) {
            minReqBalanceInWei +=
                totalBorrowsInWei.mulDiv(assetData[i], riskEngine.ltvFor(pool, assets[i]), Math.Rounding.Ceil);
        }

        return totalBalanceInWei > minReqBalanceInWei;
    }

    function fetchBalanceInWei(address pool, address position, address asset) internal view returns (uint256) {
        return IOracle(riskEngine.oracleFor(pool, asset)).getValueInEth(asset, IERC20(asset).balanceOf(position));
    }
}
