// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPool} from "../interfaces/IPool.sol";
import {IterableMap} from "../lib/IterableMap.sol";

import {BasePosition} from "./BasePosition.sol";

contract SingleCollatPosition is BasePosition {
    using SafeERC20 for IERC20;
    using IterableMap for IterableMap.IterableMapStorage;

    // single position asset; multiple debt assets
    uint256 public constant override TYPE = 0x2;

    address internal positionAsset;

    IterableMap.IterableMapStorage internal debtPools;

    /// @dev assume that funds are sent in the same txn after deposit is called
    function deposit(address asset, uint256) external override onlyPositionManager {
        if (positionAsset == address(0)) {
            positionAsset = asset;
        } else if (positionAsset != asset) {
            revert InvalidOperation();
        }
    }

    function withdraw(address asset, uint256 amt) external override onlyPositionManager {
        if (IERC20(asset).balanceOf(address(this)) == amt) {
            positionAsset = address(0);
        }
        IERC20(asset).safeTransfer(owner, amt);
    }

    function borrow(address pool, uint256 amt) external override onlyPositionManager {
        debtPools.set(pool, debtPools.get(pool) + amt);
    }

    function repay(address pool, uint256 amt) external override onlyPositionManager {
        debtPools.set(pool, debtPools.get(pool) - amt);
        IERC20(IPool(pool).asset()).safeTransfer(pool, amt);
    }

    function exec(address target, bytes calldata data) external override onlyPositionManager {
        (bool success,) = target.call(data);
        if (!success) revert InvalidOperation();
    }

    function getAssets() external view override returns (address[] memory) {
        address[] memory assets = new address[](1);
        assets[0] = positionAsset;
        return assets;
    }

    function getDebtPools() external view override returns (address[] memory) {
        return debtPools.getKeys();
    }
}
