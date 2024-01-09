// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPool} from "./interfaces/IPool.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract HealthCheck {
    using Math for uint256;

    function checkT1(address position) internal view returns (bool) {
        IPool pool = IPool(IPosition(position).getDebtPools()[0]);
        address debtAsset = pool.asset();
        uint256 borrows = pool.convertToWei(debtAsset, pool.getBorrowsOf(position));
        uint256 balance = 0;
        address[] memory assets = IPosition(position).getAssets();
        for (uint256 i; i < assets.length; ++i) {
            balance += pool.convertToWei(assets[i], IERC20(assets[i]).balanceOf(position));
        }
        return borrows / balance > 0; // TODO LTV check goes here
    }

    function checkT2(address position) internal view returns (bool) {
        uint256 borrows = 0;
        address[] memory debtPools = IPosition(position).getDebtPools();
        uint256[] memory debts = new uint256[](debtPools.length);
        for (uint256 i; i < debtPools.length; ++i) {
            IPool pool = IPool(debtPools[i]);
            debts[i] = pool.getBorrowsOf(position);
            borrows += pool.convertToWei(pool.asset(), debts[i]);
        }
        address positionAsset = IPosition(position).getAssets()[0];
        uint256 balance = 0;
        uint256 notionalBalance = IERC20(positionAsset).balanceOf(position);
        for (uint256 i; i < debtPools.length; ++i) {
            debts[i] = debts[i].mulDiv(1e18, borrows, Math.Rounding.Ceil);
            balance += debts[i].mulDiv(IPool(debtPools[i]).convertToWei(positionAsset, notionalBalance), 1e18);
        }
        return borrows / balance > 0; // TODO LTV check goes here
    }
}
