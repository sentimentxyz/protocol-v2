// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPool} from "./interfaces/IPool.sol";
import {IPosition} from "./interfaces/IPosition.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PositionManager {
    using SafeERC20 for IERC20;

    enum Operation {
        Exec,
        Repay,
        Borrow,
        Deposit,
        Withdraw,
        UpdateAsset
    }

    struct Action {
        Operation op;
        address target;
        bytes data;
    }

    /// @dev auth[x][y] stores whether address x is authorized to operate on position y
    mapping(address => mapping(address => bool)) auth;

    error Unauthorized();
    error InvalidOperation();

    function newPosition() external {
        // TODO deploy new position for msg.sender
        // auth[msg.sender][position] = true;
    }

    function setAuth(address user, address position, bool isAuthorized) external {
        if (msg.sender == IPosition(position).owner()) revert Unauthorized();
        auth[user][position] = isAuthorized;
    }

    function process(address position, Action[] calldata actions) external {
        if (auth[msg.sender][position]) revert Unauthorized();
        for (uint256 i; i < actions.length; ++i) {
            if (actions[i].op == Operation.Exec) {
                IPosition(position).exec(actions[i].target, actions[i].data);
            } else {
                Operation op;
                address target;
                uint256 data;

                assembly {
                    let offset := mul(0xa0, i)
                    op := calldataload(add(0x64, offset))
                    target := calldataload(add(0x84, offset))
                    data := calldataload(add(0xc4, offset))
                }

                if (op == Operation.Repay) {
                    repay(position, target, data);
                } else if (op == Operation.Borrow) {
                    borrow(position, target, data);
                } else if (op == Operation.UpdateAsset) {
                    updateAsset(position, target, data);
                } else if (op == Operation.Withdraw) {
                    IPosition(position).withdraw(target, data);
                } else if (op == Operation.Deposit) {
                    IERC20(target).safeTransferFrom(msg.sender, position, data);
                } else {
                    revert InvalidOperation();
                }
            }
        }
        // TODO health check
    }

    function repay(address position, address pool, uint256 _amt) internal {
        // to repay the entire debt set amt to uint.max
        uint256 amt = (_amt == type(uint256).max) ? IPool(pool).getBorrowsOf(position) : _amt;

        IPosition(position).repay(IPool(pool).asset(), amt);
        IPool(pool).repay(position, amt);
    }

    function borrow(address position, address pool, uint256 amt) internal {
        IPosition(position).borrow(pool, amt);
        IPool(pool).borrow(position, amt);
    }

    function updateAsset(address position, address asset, uint256 data) internal {
        if (data == 0x0) {
            IPosition(position).removeAsset(asset);
        } else if (data == 0x1) {
            IPosition(position).addAsset(asset);
        }
    }

    // TODO liquidation
}
