// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPool} from "../interfaces/IPool.sol";
import {IterableSet} from "../lib/IterableSet.sol";

import {BasePosition} from "./BasePosition.sol";

contract SingleDebtPosition is BasePosition {
    using SafeERC20 for IERC20;
    using IterableSet for IterableSet.IterableSetStorage;

    // single debt pool; multiple position assets
    uint256 public constant override TYPE = 0x1;

    address internal debtPool;
    IterableSet.IterableSetStorage internal assets;

    function borrow(address pool, uint256) external override onlyPositionManager {
        if (debtPool == address(0)) {
            debtPool = pool;
        } else if (pool != debtPool) {
            revert InvalidOperation();
        }
    }

    function repay(address pool, uint256 amt) external override onlyPositionManager {
        if (pool != debtPool) revert InvalidOperation();
        if (IPool(pool).getBorrowsOf(address(this)) == amt) {
            debtPool = address(0);
        }
        IERC20(IPool(debtPool).asset()).safeTransfer(address(pool), amt);
    }

    function exec(address target, bytes calldata data) external override onlyPositionManager {
        (bool success,) = target.call(data);
        if (!success) revert InvalidOperation();
    }

    function getAssets() external view override returns (address[] memory) {
        return assets.getElements();
    }

    function getDebtPools() external view override returns (address[] memory) {
        address[] memory debtPools = new address[](1);
        debtPools[0] = debtPool;
        return debtPools;
    }

    function addAsset(address asset) external onlyPositionManager {
        assets.insert(asset);
    }

    function removeAsset(address asset) external onlyPositionManager {
        assets.remove(asset);
    }
}
