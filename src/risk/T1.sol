// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IRiskManager} from "src/interfaces/IRiskManager.sol";
import {IPosition} from "src/interfaces/IPosition.sol";
import {IPool} from "src/interfaces/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IterableMapAddress} from "src/lib/IterableMapAddress.sol";
import {RiskEngineBase} from "src/risk/RiskEngineBase.sol";

contract Type1HealthChecks is RiskEngineBase {
    /// @dev this type of position has 1 pool, and potentially more than one collateral token.
    /// @dev this also means it has more than one LTV ratio.
    /// @dev we compute the current LTV ratio for each collateral token ensuring that its less than the max LTV ratio for that token.
    function isPositionHealthy(address position) external view returns (bool) {
        IPosition _position = IPosition(position);
        IPool pool = IPool(_position.getDebtPools()[0]);

        uint256 borrowsValue = _borrowValue(position, address(pool));

        address[] memory assets = _position.getAssets();
        for (uint256 i; i < assets.length; ++i) {
            uint256 collateralValue = _collateralValue(
                position,
                address(pool),
                assets[i]
            );

            uint256 ltvBP = _computeLtv(borrowsValue, collateralValue);

            if (ltvBP > pool.ltv(assets[i])) {
                return false;
            }
        }

        return true;
    }
}



