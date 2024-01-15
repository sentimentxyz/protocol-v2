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

struct Operations {
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
    /// 0x2 is the owner
    /// 0x1 is authorized
    /// 0x0 is unauthorized
    mapping(address user => mapping(address position => uint256)) auth;
    mapping(address position => address owner) public posOwner;

    address public singleDebt;
    address public singleCollat;

    /// @dev set the pools after creation so we can inline address(this) into positions
    function setPools(address _singleDebt, address _singleCollat) external {
        if (singleDebt != address(0)) revert PoolsAlreadyInitialized();
        singleDebt = _singleDebt;
        singleCollat = _singleCollat;
    }

    function setAuth(
        address user,
        address position,
        bool _isAuthorized
    ) external {
        if (auth[user][position] != 0x2) revert Unauthorized();

        if (_isAuthorized) {
            auth[user][position] = 0x1;
        } else {
            auth[user][position] = 0x0;
        }
    }

    function processBatch(
        address[] calldata position,
        Operations[] calldata operations
    ) external {
        if (position.length != operations.length) revert LengthMismatch();

        for (uint256 i; i < position.length; ++i) {
            process(position[i], operations[i]);
        }
    }

    /// @notice A position can process a batch of Operations from its context
    /// @notice If the position is a new position the first operation must be NewPosition
    /// @notice however you can deploy newPositions within a process if you dont wish to perform actions on them
    function process(
        address position,
        Operations calldata operations
    ) public {
        if (operations.op.length != operations.data.length) revert LengthMismatch();

        if (isAuthorized(msg.sender, position)) {
            _process(position, operations);
        } else if (operations.op[0] == Operation.NewPosition) {
            // if they are not the owner or authed they may be trying to create a new position
            (PositionType posType, bytes32 _salt) = abi.decode(
                operations.data[0],
                (PositionType, bytes32)
            );

            // this will revert if someone tries to use the same salt twice
            address _pos = newPosition(posType, _salt);

            // make sure the postion they passed in was the one they just deployed
            if (_pos != position) revert Unauthorized();

            // if there is more than one operation
            if (operations.op.length > 1) {
                _process(_pos, popFrontOperation(operations));
            }
        } else {
            revert Unauthorized();
        }

        // todo!(health check)
    }

    function _process(address position, Operations memory operations) internal {
        for (uint256 i; i < operations.op.length; i++) {
            if (operations.op[i] == Operation.Exec) {
                IPosition(position).exec(address(this), operations.data[i]);
            } else if (operations.op[i] == Operation.NewPosition) {
                (PositionType posType, bytes32 _salt) = abi.decode(
                    operations.data[i],
                    (PositionType, bytes32)
                );

                newPosition(posType, _salt);
            } else if (operations.op[i] == Operation.Repay) {
                (address pool, uint256 amt) = abi.decode(
                    operations.data[i],
                    (address, uint256)
                );

                repay(position, pool, amt);
            } else if (operations.op[i] == Operation.Borrow) {
                (address pool, uint256 amt) = abi.decode(
                    operations.data[i],
                    (address, uint256)
                );

                borrow(position, pool, amt);
            } else if (operations.op[i] == Operation.Deposit) {
                (address asset, uint256 amt) = abi.decode(
                    operations.data[i],
                    (address, uint256)
                );

                deposit(position, asset, amt);
            } else if (operations.op[i] == Operation.Withdraw) {
                (address asset, address to, uint256 amt) = abi.decode(
                    operations.data[i],
                    (address, address, uint256)
                );

                withdraw(position, asset, to, amt);
            } else if (operations.op[i] == Operation.AddAsset) {
                address asset = abi.decode(operations.data[i], (address));

                addAsset(position, asset);
            } else if (operations.op[i] == Operation.RemoveAsset) {
                address asset = abi.decode(operations.data[i], (address));

                removeAsset(position, asset);
            } else {
                revert InvalidOperation();
            }
        }
    }
    
    ////////////////////////// Operation Functions //////////////////////////

    function newPosition(
        PositionType posType,
        bytes32 _salt
    ) public returns (address pos) {
        if (posType == PositionType.SingleCollatMultiDebt) {
            pos = address(new BeaconProxy{salt: _salt}(singleCollat, ""));
        } else if (posType == PositionType.SingleDebtMultiCollat) {
            pos = address(new BeaconProxy{salt: _salt}(singleDebt, ""));
        } else {
            revert UnknownPool();
        }

        posOwner[pos] = msg.sender;
        auth[msg.sender][pos] = 0x2;
    }

    function deposit(
        address position,
        address asset,
        uint256 amt
    ) internal {
        IERC20(asset).safeTransferFrom(msg.sender, position, amt);
    }

    function withdraw(
        address position,
        address asset,
        address to,
        uint256 amt
    ) internal {
        IPosition(position).withdraw(asset, to, amt);
    }

    function repay(address position, address pool, uint256 _amt) internal {
        // to repay the entire debt set amt to uint.max
        uint256 amt = (_amt == type(uint256).max)
            ? IPool(pool).getBorrowsOf(position)
            : _amt;

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

    ////////////////////////// View / Pure //////////////////////////

    function isAuthorized(
        address user,
        address position
    ) public view returns (bool) {
        return auth[user][position] > 0;
    }

    /// Since we havent copied over the array to memory yet this is basically the same
    /// as what the compiler would do for an implicit conversion from calldata -> memory
    function popFrontOperation(
        Operations calldata operations
    ) internal pure returns (Operations memory) {
        uint256 len = operations.op.length;
        Operations memory _operations = Operations({
            op: new Operation[](len - 1),
            data: new bytes[](len - 1)
        });

        // weve already done length match checks
        for (uint256 i = 1; i < len; i++) {
            _operations.op[i - 1] = operations.op[i];
            _operations.data[i - 1] = operations.data[i];
        }

        return _operations;
    }
}
