// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IRiskManager} from "src/interfaces/IRiskManager.sol";
import {IPosition} from "src/interfaces/IPosition.sol";
import {IPool} from "src/interfaces/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HealthCheck is IRiskManager {
    function isPositionHealthy(
        address position
    ) external view override returns (bool) {
        IPosition _position = IPosition(position);

        if (_position.TYPE() == 1) {
            return checkType1(position);
        } else if (_position.TYPE() == 2) {
            return checkType2(position);
        } else {
            revert PoolType();
        }
    }

    /// @dev this type of position has 1 pool, and potentially more than one collateral token.
    /// @dev this also means it has more than one LTV ratio.
    /// @dev we compute the current LTV ratio for each collateral token ensuring that its less than the max LTV ratio for that token.
    function checkType1(address position) internal view returns (bool) {
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

    /// @dev this type of position has multiple pools, and only one collateral token.
    /// @dev for each pool we get the LTV and compute the minimum amount of collateral needed to be healthy.
    /// @dev we then sum up the total amount of collateral needed and compare it to the current amount of collateral.
    function checkType2(address position) internal view returns (bool) {
        IPosition _position = IPosition(position);
        address asset = _position.getAssets()[0];
        uint256 totalCollateralNeeded;

        address[] memory pools = _position.getDebtPools();
        for (uint256 i; i < pools.length; ++i) {
            uint256 borrowsValue = _borrowValue(position, pools[i]);
            uint256 ltvBP = IPool(pools[i]).ltv(asset);

            totalCollateralNeeded = borrowsValue * 10000 / ltvBP;
        }
        
        // todo how to use the indivual oracles for each pool
        return _collateralValue(position, pools[0], asset) > totalCollateralNeeded;
    }

    function ltv(
        address position,
        address pool,
        address token
    ) public view override returns (uint256) {
        return
            _computeLtv(
                _borrowValue(position, pool),
                _collateralValue(position, pool, token)
            );
    }

    function _collateralValue(
        address position,
        address pool,
        address token
    ) internal view returns (uint256) {
        return IPool(pool).value(token, IERC20(token).balanceOf(position));
    }

    function _borrowValue(
        address position,
        address pool
    ) internal view returns (uint256) {
        return
            IPool(pool).value(
                IPool(pool).asset(),
                IPool(pool).getBorrowsOf(position)
            );
    }

    function _computeLtv(
        uint256 borrowValue,
        uint256 collateralValue
    ) internal pure returns (uint256) {
        return (borrowValue * 100) / collateralValue;
    }
}
