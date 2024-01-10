// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPool} from "./interfaces/IPool.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PositionType} from "src/positions/BasePosition.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

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
    Operation[] op;
    bytes[] data;
}

contract PositionManager {
    using SafeERC20 for IERC20;
    error Unauthorized();
    error InvalidOperation();
    error UnknownPool();
    error PoolsAlreadyInitialized();
    error LengthMismatch();

    /// @dev auth[x][y] stores whether address x is authorized to operate on position y
    mapping(address user => mapping(address position => bool)) auth;
    mapping(address position => address owner) public posOwner;

    address public singleDebt;
    address public singleCollat;

    /// @dev set the pools after creation so we can inline address(this) into positions
    function setPools(address _singleDebt, address _singleCollat) external {
        if (singleDebt != address(0)) revert PoolsAlreadyInitialized();
        singleDebt = _singleDebt;
        singleCollat = _singleCollat;
    }

    function setAuth(address user, address position, bool isAuthorized) external {
        if (msg.sender == posOwner[position]) revert Unauthorized();
        auth[user][position] = isAuthorized;
    }

    function process(address[] position, Action[] calldata actions) external {
        if (position.length != actions.length) revert LengthMismatch();

        for (uint256 i; i < position.length; ++i) {
            if (actions[i].op.length != actions[i].data.length) revert LengthMismatch();
            
            // if this is the owner or they authed
            if (isAuthorized(msg.sender, position[i])) {
                _process(position[i], actions[i]);
            // if they are not the owner or authed && this is true then maybe its a position we are just making
            } else if (actions[i].op[0] == Operation.NewPosition) {
                // sanity
                if (posOwner[position[i]] != address(0)) revert InvalidOperation();

                (PositionType posType, bytes32 _salt) = abi.decode(actions[i].data[0], (PositionType, bytes32));
                // this will revert if someone tries to use the same salt twice
                address _pos = newPosition(posType, _salt);
                if (_pos != position[i]) revert Unauthorized();

                _process(_pos, actions[1:]);
            } else {
                revert Unauthorized();
            }

            // todo!(health check)
        }
    }

    function _process(address position, Action memory action) internal {
        for (uint256 i; i < action.op.length; i++) {
            if (action.op[i] == Operation.Exec) {
                IPosition(position).exec(address(this), action.data[i]);
            } else if (action.op[i] == Operation.Repay) {
                (address pool, uint256 amt) = abi.decode(action.data[i], (address, uint256));
                repay(position, pool, amt);
            } else if (action.op[i] == Operation.Borrow) {
                (address pool, uint256 amt) = abi.decode(action.data[i], (address, uint256));
                borrow(position, pool, amt);
            } else if (action.op[i] == Operation.Deposit) {
                (address asset, uint256 amt) = abi.decode(action.data[i], (address, uint256));
                IERC20(asset).safeTransferFrom(msg.sender, position, amt);
            } else if (action.op[i] == Operation.Withdraw) {
                (address asset, uint256 amt) = abi.decode(action.data[i], (address, uint256));
                IPosition(position).withdraw(asset, amt);
            } else if (action.op[i] == Operation.AddAsset) {
                (address asset) = abi.decode(action.data[i], (address));
                addAsset(position, asset);
            } else if (action.op[i] == Operation.RemoveAsset) {
                (address asset) = abi.decode(action.data[i], (address));
                removeAsset(position, asset);
            } else {
                revert InvalidOperation();
            }
        }
    }

    function newPosition(PositionType posType, bytes32 _salt) internal returns (address pos) {
        if (posType == PositionType.SingleCollatMultiDebt) {
            pos = address(new BeaconProxy{salt: _salt}(singleCollat, ""));
        } else if (posType == PositionType.SingleDebtMultiCollat) {
            pos = address(new BeaconProxy{salt: _salt}(singleDebt, ""));
        } else {
            revert UnknownPool();
        }

        poolOwner[pos] = msg.sender;
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

    function addAsset(address position, address asset) internal {
        IPosition(position).addAsset(asset);
    }

    function removeAsset(address position, address asset) internal {
        IPosition(position).removeAsset(asset);
    }

    function isAuthorized(address user, address position) public view returns (bool) {
        return auth[user][position] || msg.sender == posOwner[position];
    }

    // TODO liquidation
}
