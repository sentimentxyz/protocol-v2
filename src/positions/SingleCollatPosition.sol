// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPool} from "../interfaces/IPool.sol";
import {IterableMap} from "../lib/IterableMap.sol";

contract SingleCollatPosition {
    using SafeERC20 for IERC20;
    using IterableMap for IterableMap.IterableMapStorage;

    // single position asset; multiple debt assets
    uint256 public constant TYPE = 0x2;

    address public owner;
    address internal positionAsset;
    address public positionManager;

    IterableMap.IterableMapStorage internal debtPools;

    error InvalidOperation();
    error PositionManagerOnly();

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert PositionManagerOnly();
        _;
    }

    /// @dev assume that funds are sent in the same txn before deposit is called
    function deposit(address asset, uint256) external onlyPositionManager {
        if (positionAsset == address(0)) {
            positionAsset = asset;
        } else if (positionAsset != asset) {
            revert InvalidOperation();
        }
    }

    function withdraw(address asset, uint256 amt) external onlyPositionManager {
        if (IERC20(asset).balanceOf(address(this)) == amt) {
            positionAsset = address(0);
        }
        IERC20(asset).safeTransfer(owner, amt);
    }

    function borrow(address pool, uint256 amt) external onlyPositionManager {
        debtPools.set(pool, debtPools.get(pool) + amt);
    }

    function repay(address pool, uint256 amt) external onlyPositionManager {
        debtPools.set(pool, debtPools.get(pool) - amt);
        IERC20(IPool(pool).asset()).safeTransfer(pool, amt);
    }

    function exec(address target, bytes calldata data) external onlyPositionManager {
        (bool success,) = target.call(data);
        if (!success) revert InvalidOperation();
    }

    function getAssets() external view returns (address[] memory) {
        address[] memory assets = new address[](1);
        assets[0] = positionAsset;
        return assets;
    }

    function getDebtPools() external view returns (address[] memory) {
        return debtPools.getKeys();
    }
}
