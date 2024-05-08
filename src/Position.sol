// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {Pool} from "./Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// libraries
import {IterableSet} from "./lib/IterableSet.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Position {
    using SafeERC20 for IERC20;
    using IterableSet for IterableSet.IterableSetStorage;

    uint256 public constant VERSION = 1;

    uint256 public constant MAX_ASSETS = 5;
    uint256 public constant MAX_DEBT_POOLS = 5;

    address public immutable POSITION_MANAGER;

    IterableSet.IterableSetStorage internal debtPools;
    IterableSet.IterableSetStorage internal positionAssets;

    error Position_MaxAssetsExceeded(address position);
    error Position_MaxDebtPoolsExceeded(address position);
    error Position_ExecFailed(address position, address target);
    error Position_OnlyPositionManager(address position, address sender);

    constructor(address positionManager_) {
        POSITION_MANAGER = positionManager_;
    }

    modifier onlyPositionManager() {
        if (msg.sender != POSITION_MANAGER) revert Position_OnlyPositionManager(address(this), msg.sender);
        _;
    }

    function getDebtPools() external view returns (address[] memory) {
        return debtPools.getElements();
    }

    function getPositionAssets() external view returns (address[] memory) {
        return positionAssets.getElements();
    }

    // approve an external contract to spend funds from the position
    // this function can only be called by the position manager
    // the position manager imposes additional checks on the spender
    function approve(address token, address spender, uint256 amt) external onlyPositionManager {
        // handle tokens with non-standard return values using forceApprove
        // handle tokens that force setting approval to zero first using forceApprove
        IERC20(token).forceApprove(spender, amt);
    }

    // transfer assets from a position to a given external contract
    // since this function can only be called by the position manager
    // any additional checks must be implemented on the position manager
    function transfer(address to, address asset, uint256 amt) external onlyPositionManager {
        // handle tokens with non-standard return values using safeTransfer
        IERC20(asset).safeTransfer(to, amt);
    }

    // intereact with external contracts and arbitrary calldata
    // any target and calldata validation must be implementeed in the position manager
    function exec(address target, bytes calldata data) external onlyPositionManager {
        (bool success,) = target.call(data);
        if (!success) revert Position_ExecFailed(address(this), target);
    }

    function addAsset(address asset) external onlyPositionManager {
        positionAssets.insert(asset);
        if (positionAssets.length() > MAX_ASSETS) revert Position_MaxAssetsExceeded(address(this));
    }

    function removeAsset(address asset) external onlyPositionManager {
        positionAssets.remove(asset);
    }

    function borrow(address pool, uint256) external onlyPositionManager {
        debtPools.insert(pool);
        if (debtPools.length() > MAX_DEBT_POOLS) revert Position_MaxDebtPoolsExceeded(address(this));
    }

    function repay(address pool, uint256) external onlyPositionManager {
        if (Pool(pool).getBorrowsOf(address(this)) == 0) debtPools.remove(pool);
    }
}
