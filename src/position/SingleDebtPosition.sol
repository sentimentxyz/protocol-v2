// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import {Pool} from "../Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// libraries
import {Errors} from "src/lib/Errors.sol";
import {IterableSet} from "../lib/IterableSet.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// contracts
import {BasePosition} from "./BasePosition.sol";

/*//////////////////////////////////////////////////////////////
                        SingleDebtPosition
//////////////////////////////////////////////////////////////*/

// TYPE -- 0x1
// single debt pool; multiple position assets
// single debt positions are structured to allow using multiple assets as collateral
// the borrower is only allowed to borrow from one debt pool at a time
// this implies that any collateral not supported by the current debt pool is ignored risk-wise
contract SingleDebtPosition is BasePosition {
    using SafeERC20 for IERC20;
    using IterableSet for IterableSet.IterableSetStorage;

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    uint256 public constant override TYPE = 0x1;

    // debt pool that is currently being borrowed from
    address internal debtPool;

    // iterable set that stores a list of assets being used as collateral
    IterableSet.IterableSetStorage internal assets;

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor(address _positionManager) BasePosition(_positionManager) {}

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    // IPosition compliant function to fetch assets held by the position
    function getAssets() external view override returns (address[] memory) {
        return assets.getElements();
    }

    // IPosition compliant way to fetch all debt pools that the position is currently borrowing from
    // will always return a singleton array since there's at most one active debt pool at any time
    function getDebtPools() external view override returns (address[] memory) {
        if (debtPool == address(0)) return new address[](0);

        // debtPool is the only pool to be returned
        address[] memory debtPools = new address[](1);
        debtPools[0] = debtPool;
        return debtPools;
    }

    /*//////////////////////////////////////////////////////////////
                       State Mutating Functions
    //////////////////////////////////////////////////////////////*/

    // signal borrow without any transfer of assets
    // should be followed by Pool.borrow() to actually transfer assets
    // must implement any position-specific borrow validation
    function borrow(address pool, uint256) external override onlyPositionManager {
        if (debtPool == address(0)) {
            debtPool = pool;
        } else if (pool != debtPool) {
            revert Errors.InvalidBorrow();
        }
    }

    // transfer assets to be repaid in order to decrease debt
    // must be followed by Pool.repay() to trigger debt repayment
    // must implement repay validation, if any
    function repay(address pool, uint256 amt) external override onlyPositionManager {
        if (pool != debtPool) revert Errors.InvalidRepay();
        if (Pool(pool).getBorrowsOf(address(this)) == amt) {
            debtPool = address(0);
        }
        IERC20(Pool(pool).asset()).safeTransfer(address(pool), amt);
    }

    // register a new asset to be used collateral in the position
    // must no-op if asset is already being used as collateral
    // must implement any position specifc validation
    function addAsset(address asset) external override onlyPositionManager {
        assets.insert(asset);
    }

    // deregister an asset from being used as collateral in the position
    // must no-op if the asset wasn't being used as collateral in the first place
    // must implement any position specifc validation
    function removeAsset(address asset) external override onlyPositionManager {
        assets.remove(asset);
    }
}
