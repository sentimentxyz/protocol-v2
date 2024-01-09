// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPool} from "./interfaces/IPool.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HealthCheck {
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
        // TODO health check for type 0x2 positions
    }
}
