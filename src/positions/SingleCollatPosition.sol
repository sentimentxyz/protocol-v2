// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Pool} from "../Pool.sol";
import {IterableSet} from "../lib/IterableSet.sol";

import {BasePosition} from "./BasePosition.sol";

// TYPE -- 0x2
// single position asset; multiple debt assets
// single collateral positions are structured to allow borrowing from multiple debt pools
// these debt pools may have different debt assets
// the borrower is only allowed to use one type of collateral asset at a given time
// implicitly, all debt pools must support the position asset as collateral
contract SingleCollatPosition is BasePosition {
    using SafeERC20 for IERC20;
    using IterableSet for IterableSet.IterableSetStorage;

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    uint256 public constant override TYPE = 0x2;

    // collateral asset token - this is the only asset considered as collateral
    address internal positionAsset;

    // iterable set storing a list of debt pools that the position is currently borrowing from
    IterableSet.IterableSetStorage internal debtPools;

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

    // IPosition compliant function to fetch assets held by the position
    // return value will always be a singleton asset since there's only one
    // collateral asset registered by the position at a given point in time
    function getAssets() external view override returns (address[] memory) {
        // positionAsset is the only asset to be returned
        address[] memory assets = new address[](1);
        assets[0] = positionAsset;
        return assets;
    }

    // IPosition compliant way to fetch all debt pools that the position is currently borrowing from
    function getDebtPools() external view override returns (address[] memory) {
        return debtPools.getElements();
    }

    /*//////////////////////////////////////////////////////////////
                       State Mutating Functions
    //////////////////////////////////////////////////////////////*/

    // signal borrow without any transfer of assets
    // should be followed by Pool.borrow() to actually transfer assets
    // must implement any position-specific borrow validation
    function borrow(address pool, uint256) external override onlyPositionManager {
        // TODO check if pool supports position asset as collateral
        debtPools.insert(pool);
    }

    // transfer assets to be repaid in order to decrease debt
    // must be followed by Pool.repay() to trigger debt repayment
    // must implement repay validation, if any
    function repay(address pool, uint256 amt) external override onlyPositionManager {
        if (Pool(pool).getBorrowsOf(address(this)) == amt) debtPools.remove(pool);
        IERC20(Pool(pool).asset()).safeTransfer(pool, amt);
    }

    // intereact with external contracts and arbitrary calldata
    // assume any target and calldata validation is done by the position manager
    function exec(address target, bytes calldata data) external override onlyPositionManager {
        (bool success,) = target.call(data);
        if (!success) revert InvalidOperation();
    }

    // register a new asset to be used collateral in the position
    // must no-op if asset is already being used as collateral
    // must implement any position specifc validation
    function addAsset(address asset) external override onlyPositionManager {
        positionAsset = asset;
    }

    // deregister an asset from being used as collateral in the position
    // must no-op if the asset wasn't being used as collateral in the first place
    // must implement any position specifc validation
    function removeAsset(address asset) external override onlyPositionManager {
        if (positionAsset == asset) {
            positionAsset = address(0);
        }
    }
}
