// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Pool} from "../Pool.sol";
import {IterableSet} from "../lib/IterableSet.sol";

import {BasePosition} from "./BasePosition.sol";

contract SingleDebtPosition is BasePosition {
    using SafeERC20 for IERC20;
    using IterableSet for IterableSet.IterableSetStorage;

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    // single debt pool; multiple position assets
    uint256 public constant override TYPE = 0x1;

    address internal debtPool;
    IterableSet.IterableSetStorage internal assets;

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address _positionManager) public override initializer {
        BasePosition.initialize(_positionManager);
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    function getAssets() external view override returns (address[] memory) {
        return assets.getElements();
    }

    function getDebtPools() external view override returns (address[] memory) {
        address[] memory debtPools = new address[](1);
        debtPools[0] = debtPool;
        return debtPools;
    }

    /*//////////////////////////////////////////////////////////////
                       State Mutating Functions
    //////////////////////////////////////////////////////////////*/

    function borrow(address pool, uint256) external override onlyPositionManager {
        if (debtPool == address(0)) {
            debtPool = pool;
        } else if (pool != debtPool) {
            revert InvalidOperation();
        }
    }

    function repay(address pool, uint256 amt) external override onlyPositionManager {
        if (pool != debtPool) revert InvalidOperation();
        if (Pool(pool).getBorrowsOf(address(this)) == amt) {
            debtPool = address(0);
        }
        IERC20(Pool(debtPool).asset()).safeTransfer(address(pool), amt);
    }

    function exec(address target, bytes calldata data) external override onlyPositionManager {
        (bool success,) = target.call(data);
        if (!success) revert InvalidOperation();
    }

    function addAsset(address asset) external override onlyPositionManager {
        assets.insert(asset);
    }

    function removeAsset(address asset) external override onlyPositionManager {
        assets.remove(asset);
    }
}
