// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IRiskManager} from "src/interfaces/IRiskManager.sol";
import {IPosition} from "src/interfaces/IPosition.sol";
import {IPool} from "src/interfaces/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IterableMapAddress} from "src/lib/IterableMapAddress.sol";

/// @notice define an abstract class so actual implemntations can easily use the state layout
abstract contract RiskEngineBase is IRiskManager {
    using IterableMapAddress for IterableMapAddress.IterableMapAddressStorage;

    mapping(address pool => mapping(address token => uint256)) internal minimumLTV;
    mapping(address pool => IterableMapAddress.IterableMapAddressStorage) internal oracles;

    /// @notice the supported collateral tokens of a pool
    function supportedCollateral(address pool) public view returns (address[] memory) {
        return oracles[pool].getKeys();
    }

    /// @notice the ltv of a position
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

    /// @notice the collateral value of token in a position denominated in eth
    function _collateralValue(
        address position,
        address pool,
        address token
    ) internal view returns (uint256) {
        return IPool(pool).value(token, IERC20(token).balanceOf(position));
    }

    /// @notice the borrow value in eth of a position from a pool
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
