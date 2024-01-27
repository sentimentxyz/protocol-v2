// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Pool} from "../Pool.sol";
import {IterableSet} from "../lib/IterableSet.sol";

import {BasePosition} from "./BasePosition.sol";

contract SingleCollatPosition is BasePosition {
    using SafeERC20 for IERC20;
    using IterableSet for IterableSet.IterableSetStorage;

    // single position asset; multiple debt assets
    uint256 public constant override TYPE = 0x2;

    address internal positionAsset;

    IterableSet.IterableSetStorage internal debtPools;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _positionManager) public override initializer {
        BasePosition.initialize(_positionManager);
    }

    function borrow(address pool, uint256) external override onlyPositionManager {
        debtPools.insert(pool);
    }

    function repay(address pool, uint256 amt) external override onlyPositionManager {
        if (Pool(pool).getBorrowsOf(address(this)) == amt) debtPools.remove(pool);
        IERC20(Pool(pool).asset()).safeTransfer(pool, amt);
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
        return debtPools.getElements();
    }

    function addAsset(address asset) external onlyPositionManager {
        positionAsset = asset;
    }

    function removeAsset(address asset) external onlyPositionManager {
        if (positionAsset == asset) {
            positionAsset = address(0);
        }
    }
}
