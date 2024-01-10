// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPool} from "./interfaces/IPool.sol";
import {IPosition} from "./interfaces/IPosition.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract PositionManager is Ownable, Pausable {
    using SafeERC20 for IERC20;

    enum Operation {
        Exec,
        Repay,
        Borrow,
        Deposit,
        Withdraw,
        AddAsset,
        RemoveAsset
    }

    struct Action {
        Operation op;
        address target;
        bytes data;
    }

    mapping(uint256 => address) public beaconFor;
    /// @dev auth[x][y] stores whether address x is authorized to operate on position y
    mapping(address => mapping(address => uint160)) public auth;

    error Unauthorized();
    error InvalidOperation();

    constructor() Ownable(msg.sender) {}

    function newPosition(address owner, uint256 positionType, bytes32 salt) external {
        if (beaconFor[positionType] == address(0)) revert InvalidOperation();
        address position = address(new BeaconProxy{salt: salt}(beaconFor[positionType], ""));
        auth[position][address(0)] = uint160(owner);
        auth[owner][position] = 0x1;
    }

    function setAuth(address user, address position, bool isAuthorized) external {
        if (auth[msg.sender][position] == 0x1) revert Unauthorized();
        auth[user][position] = isAuthorized ? 0x2 : 0x0;
    }

    function process(address position, Action[] calldata actions) external {
        if (auth[msg.sender][position] == 0) revert Unauthorized();
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
                } else if (op == Operation.AddAsset) {
                    IPosition(position).addAsset(target);
                } else if (op == Operation.RemoveAsset) {
                    IPosition(position).removeAsset(target);
                } else if (op == Operation.Withdraw) {
                    IPosition(position).withdraw(address(auth[position][address(0)]), target, data);
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

    // TODO liquidation

    // Admin Functions
    function setBeacon(uint256 positionType, address beacon) external onlyOwner {
        beaconFor[positionType] = beacon;
    }
}
