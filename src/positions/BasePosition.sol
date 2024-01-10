// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

enum PositionType {
    SingleCollatMultiDebt,
    SingleDebtMultiCollat
}

abstract contract BasePosition {
    using SafeERC20 for IERC20;

    address public immutable positionManager;

    error InvalidOperation();
    error PositionManagerOnly();

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert PositionManagerOnly();
        _;
    }

    constructor(address _positionManager) {
        positionManager = _positionManager;
    }

    function TYPE() external view virtual returns (PositionType);

    function getAssets() external view virtual returns (address[] memory);

    function getDebtPools() external view virtual returns (address[] memory);

    function repay(address pool, uint256 amt) external virtual;

    function borrow(address pool, uint256 amt) external virtual;

    function exec(address target, bytes calldata data) external virtual;

    function withdraw(address asset, address to, uint256 amt) external onlyPositionManager {
        IERC20(asset).safeTransfer(to, amt);
    }
}
