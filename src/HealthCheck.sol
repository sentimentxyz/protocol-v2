// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IRiskManager} from "src/interfaces/IRiskManager.sol";
import (IPosition) from "src/interfaces/IPosition.sol";
import {IPool} from "src/interfaces/IPool.sol";

contract HealthCheck is IRiskManager {
    function isPositionHealthy(address position) external override returns (bool) {
        return true;
    }

    /// @dev this type of position has 1 pool, and potentially more than one collateral token.
    /// @dev this also means it has more than one LTV ratio.
    /// @dev we compute the current LTV ratio for each collateral token ensuring that its less than the max LTV ratio for that token.
    function checkType1(address position) external returns (bool) {
        IPosition position = IPosition(position);
        IPool pool = IPool(position.getDebtPools()[0]);
        uint256 borrowsValue = pool.value(pool.asset(), pool.getBorrowsOf(position));
    }
}