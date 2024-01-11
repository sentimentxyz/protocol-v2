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
        RemoveAsset,
        NewPosition
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

    function setAuth(address user, address position, bool isAuthorized) external {
        if (auth[msg.sender][position] != 0x1) revert Unauthorized();
        auth[user][position] = isAuthorized ? 0x2 : 0x0;
    }

    function process(address position, Action[] calldata actions) external {
        if (auth[msg.sender][position] == 0) revert Unauthorized();
        for (uint256 i; i < actions.length; ++i) {
            if (actions[i].op == Operation.Exec) {
                IPosition(position).exec(actions[i].target, actions[i].data);
            } else if (actions[i].op == Operation.NewPosition) {
                (uint256 positionType, bytes32 salt) = abi.decode(actions[i].data, (uint256, bytes32));
                newPosition(actions[i].target, positionType, salt);
                if (position != newPosition(actions[i].target, positionType, salt)) revert InvalidOperation();
            } else {
                uint256 data = abi.decode(actions[i].data, (uint256));
                if (actions[i].op == Operation.Repay) {
                    repay(position, actions[i].target, data);
                } else if (actions[i].op == Operation.Borrow) {
                    borrow(position, actions[i].target, data);
                } else if (actions[i].op == Operation.AddAsset) {
                    IPosition(position).addAsset(actions[i].target);
                } else if (actions[i].op == Operation.RemoveAsset) {
                    IPosition(position).removeAsset(actions[i].target);
                } else if (actions[i].op == Operation.Withdraw) {
                    IPosition(position).withdraw(address(auth[position][address(0)]), actions[i].target, data);
                } else if (actions[i].op == Operation.Deposit) {
                    IERC20(actions[i].target).safeTransferFrom(msg.sender, position, data);
                } else {
                    revert InvalidOperation();
                }
            }
        }
        // TODO health check
    }

    function newPosition(address owner, uint256 positionType, bytes32 salt) internal returns (address) {
        if (beaconFor[positionType] == address(0)) revert InvalidOperation();
        address position = address(new BeaconProxy{salt: salt}(beaconFor[positionType], ""));
        auth[position][address(0)] = uint160(owner);
        auth[owner][position] = 0x1;
        return position;
    }

    function repay(address position, address pool, uint256 _amt) internal {
        // to repay the entire debt set _amt to uint.max
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
