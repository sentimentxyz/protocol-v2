// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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

    constructor() {
        _disableInitializers();
    }

    function initialize(address _positionManager) public virtual initializer {
        positionManager = _positionManager;
    }

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

    function approve(address token, address spender, uint256 amt) external onlyPositionManager {
        IERC20(token).forceApprove(spender, amt);
    }

    function transfer(address to, address asset, uint256 amt) external onlyPositionManager {
        IERC20(asset).safeTransfer(to, amt);
    }
}
