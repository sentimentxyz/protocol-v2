// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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

    uint256 public constant TYPE = 1;

    RiskEngine public immutable riskEngine;

    constructor(address _riskEngine) {
        riskEngine = RiskEngine(_riskEngine);
    }

    function isPositionHealthy(address position) external view returns (bool) {
        address pool = IPosition(position).getDebtPools()[0];

        address[] memory assets = IPosition(position).getAssets();
        uint256[] memory assetData = new uint256[](assets.length);

        uint256 totalBalanceInWei;
        for (uint256 i; i < assets.length; ++i) {
            uint256 balanceInWei = collateralValue(pool, position, assets[i]);

            // assetData[i] -> collateral value of asset[i]
            assetData[i] = balanceInWei;
            totalBalanceInWei += balanceInWei;
        }

        for (uint256 i; i < assets.length; ++i) {
            // assetData[i] -> fraction of total account balance in asset[i]
            assetData[i] = assetData[i].mulDiv(1e18, totalBalanceInWei, Math.Rounding.Floor);
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

    /// @notice the vaule of asset of a position in eth according to the pools oracle
    function collateralValue(address pool, address position, address asset) internal view returns (uint256) {
        return IOracle(riskEngine.oracleFor(pool, asset)).getValueInEth(asset, IERC20(asset).balanceOf(position));
    }
}
