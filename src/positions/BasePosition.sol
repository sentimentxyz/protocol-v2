// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// types
import {IPosition} from "../interfaces/IPosition.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// contracts
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract BasePosition is Initializable, IPosition {
    using SafeERC20 for IERC20;

    address public positionManager;

    error InvalidOperation();
    error PositionManagerOnly();

    // TODO INIT

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert PositionManagerOnly();
        _;
    }

    function TYPE() external view virtual returns (uint256);
    function getAssets() external view virtual returns (address[] memory);
    function getDebtPools() external view virtual returns (address[] memory);

    function repay(address pool, uint256 amt) external virtual;
    function borrow(address pool, uint256 amt) external virtual;
    function exec(address target, bytes calldata data) external virtual;

    function transfer(address to, address asset, uint256 amt) external onlyPositionManager {
        IERC20(asset).safeTransfer(to, amt);
    }
}
