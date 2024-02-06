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

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/
    // position manager associated with this position
    // this cannot be modified but is mutable to comply with the init deploy pattern
    address public positionManager;

    error InvalidOperation();
    error PositionManagerOnly();

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address _positionManager) public virtual initializer {
        positionManager = _positionManager;
    }

    /*//////////////////////////////////////////////////////////////
                              Modifiers
    //////////////////////////////////////////////////////////////*/

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert PositionManagerOnly();
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

    function TYPE() external view virtual returns (uint256);
    function getAssets() external view virtual returns (address[] memory);
    function getDebtPools() external view virtual returns (address[] memory);

    /*//////////////////////////////////////////////////////////////
                   Virtual State Mutating Functions
    //////////////////////////////////////////////////////////////*/

    function repay(address pool, uint256 amt) external virtual;
    function borrow(address pool, uint256 amt) external virtual;
    function exec(address target, bytes calldata data) external virtual;
}
