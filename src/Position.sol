// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPool} from "./interfaces/IPool.sol";
import {IterableMap} from "./lib/IterableMap.sol";

contract Position {
    using SafeERC20 for IERC20;
    using IterableMap for IterableMap.IterableMapStorage;

    // single debt pool; multiple position assets
    uint8 public constant TYPE = 0x1;

    address public owner;
    address public debtPool;
    address public positionManager;

    IterableMap.IterableMapStorage internal assets;

    error InvalidOperation();
    error PositionManagerOnly();

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert PositionManagerOnly();
        _;
    }

    /// @dev assume that funds are sent in the same txn before deposit is called
    function deposit(address asset, uint256 amt) external onlyPositionManager {
        assets.set(asset, amt);
    }

    function withdraw(address asset, uint256 amt) external onlyPositionManager {
        assets.set(asset, assets.get(asset) - amt);
        IERC20(asset).safeTransfer(owner, amt);
    }

    function borrow(address pool, uint256) external onlyPositionManager {
        if (debtPool == address(0)) {
            debtPool = pool;
        } else if (pool != debtPool) {
            revert InvalidOperation();
        }
    }

    function repay(address _pool, uint256 _amt) external onlyPositionManager {
        if (_pool != debtPool) revert InvalidOperation();
        IPool pool = IPool(_pool);
        uint256 amt = (_amt == type(uint256).max) ? pool.getBorrowsOf(address(this)) : _amt;
        IERC20(IPool(debtPool).asset()).safeTransfer(address(pool), amt);
        if (IPool(pool).repay(address(this), amt) == 0) {
            debtPool = address(0);
        }
    }

    function exec(address target, uint256 amt, bytes calldata data) external onlyPositionManager {
        (bool success,) = target.call{value: amt}(data);
        if (!success) revert InvalidOperation();
    }

    function getAssets() external view returns (address[] memory) {
        return assets.getKeys();
    }

    function getDebtPools() external view returns (address[] memory) {
        address[] memory debtPools = new address[](1);
        debtPools[0] = debtPool;
        return debtPools;
    }
}
