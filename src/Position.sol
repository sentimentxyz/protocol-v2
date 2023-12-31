// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPool} from "./interfaces/IPool.sol";

contract Position {
    using SafeERC20 for IERC20;

    // single debt pool; multiple position assets
    uint8 public constant TYPE = 0x1;

    address public owner;
    address public debtPool;
    address public positionManager;

    address[] public assets;
    mapping(address => uint256) balanceOf;

    error InvalidOperation();
    error PositionManagerOnly();

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert PositionManagerOnly();
        _;
    }

    function deposit(address asset, uint256 amt) external onlyPositionManager {
        if (balanceOf[asset] == 0) assets.push(asset);
        balanceOf[asset] = amt;
    }

    function withdraw(address asset, uint256 amt) external onlyPositionManager {
        if ((balanceOf[asset] -= amt) == 0) {
            // TODO remove from assets
        }
        IERC20(asset).safeTransfer(owner, amt);
    }

    function borrow(address pool, uint256) external onlyPositionManager {
        if (debtPool == address(0)) {
            debtPool = pool;
        } else if (pool != debtPool) {
            revert InvalidOperation();
        }
    }

    function repay(address pool, uint256 _amt) external onlyPositionManager {
        if (pool != debtPool) revert InvalidOperation();
        uint256 amt = (_amt == type(uint256).max) ? IPool(pool).getBorrowsOf(address(this)) : _amt;
        IERC20(IPool(debtPool).asset()).safeTransfer(pool, amt);
        if (IPool(pool).repay(address(this), amt) == 0) {
            debtPool = address(0);
        }
    }

    function exec(address target, uint256 amt, bytes calldata data) external onlyPositionManager {
        (bool success,) = target.call{value: amt}(data);
        if (!success) revert InvalidOperation();
    }
}
