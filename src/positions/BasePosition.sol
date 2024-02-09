// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {IPosition} from "../interfaces/IPosition.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// libraries
import {Errors} from "src/lib/Errors.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// contracts
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract BasePosition is IPosition {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    // position manager associated with this position
    address public immutable positionManager;

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor(address _positionManager) {
        positionManager = _positionManager;
    }

    /*//////////////////////////////////////////////////////////////
                              Modifiers
    //////////////////////////////////////////////////////////////*/

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert Errors.PositionManagerOnly();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           Base Operations
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                        Virtual View Functions
    //////////////////////////////////////////////////////////////*/

    // position type
    // must not repeat across all position types
    // position types shouldn't be reused for any reason except upgrades
    function TYPE() external view virtual returns (uint256);

    // fetch a list of all the assets being used as collateral in the position
    function getAssets() external view virtual returns (address[] memory);

    // fetch a list of all pools that the position is borrowing from
    // returns the address of the debt pools and not the debt asset themselves
    function getDebtPools() external view virtual returns (address[] memory);

    /*//////////////////////////////////////////////////////////////
                   Virtual State Mutating Functions
    //////////////////////////////////////////////////////////////*/

    // transfer assets to be repaid in order to decrease debt
    // must be followed by Pool.repay() to trigger debt repayment
    // any position-specfic repay validation should be implemented within this function
    function repay(address pool, uint256 amt) external virtual;

    // signal borrow without any transfer of assets
    // should be followed by Pool.borrow() to actually transfer assets
    // any position specific borrow validation should be implemented within this function
    function borrow(address pool, uint256 amt) external virtual;

    // intereact with external contracts and arbitrary calldata
    // any target and calldata validation must be implementeed in the position manager
    function exec(address target, bytes calldata data) external virtual;

    // register a new asset to be used collateral in the position
    // any position specific validation should be implemented within this function
    // must no-op if asset is already being used as collateral
    function addAsset(address asset) external virtual;

    // deregister an asset from being used as collateral in the position
    // any position specific validation should be implemented within this function
    // must no-op if the asset wasn't being used as collateral in the first place
    function removeAsset(address asset) external virtual;
}
