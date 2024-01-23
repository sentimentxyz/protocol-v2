// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Interfaces
import {Pool} from "./Pool.sol";
import {RiskEngine} from "./RiskEngine.sol";
import {IPosition} from "./interfaces/IPosition.sol";
// Libraries
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// Contracts
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract PositionManager is Ownable, Pausable {
    using SafeERC20 for IERC20;

    address public riskEngine;

    mapping(address => address) public ownerFor; // position => owner
    mapping(uint256 => address) public beaconFor; // position type => beacon
    /// @dev auth[x][y] stores whether address x is authorized to operate on position y
    mapping(address => mapping(address => bool)) public auth;

    error Unauthorized();
    error InvalidOperation();
    error HealthCheckFailed();

    constructor() Ownable(msg.sender) {}

    function setAuth(address user, address position, bool isAuthorized) external {
        if (!auth[msg.sender][position]) revert Unauthorized();
        auth[user][position] = isAuthorized;
    }

    enum Operation {
        Exec,
        Repay,
        Borrow,
        Deposit,
        Transfer,
        AddAsset,
        RemoveAsset,
        NewPosition
    }

    struct Action {
        Operation op;
        address target;
        bytes data;
    }

    function process(address position, Action[] calldata actions) external {
        for (uint256 i; i < actions.length; ++i) {
            if (actions[i].op == Operation.NewPosition) {
                // Deploy New Position
                (uint256 positionType, bytes32 salt) = abi.decode(actions[i].data, (uint256, bytes32));
                if (ownerFor[position] != address(0)) revert InvalidOperation();
                if (position != newPosition(actions[i].target, positionType, salt)) revert InvalidOperation();
                continue;
            }

            // Caller needs to be authorized for every other operation
            if (!auth[msg.sender][position]) revert Unauthorized();

            if (actions[i].op == Operation.Exec) {
                // Execute arbitrary calldata on position
                IPosition(position).exec(actions[i].target, actions[i].data);
            } else if (actions[i].op == Operation.Transfer) {
                // Transfer assets out of position
                (address asset, uint256 amt) = abi.decode(actions[i].data, (address, uint256));
                IPosition(position).transfer(actions[i].target, asset, amt);
            } else {
                uint256 data = abi.decode(actions[i].data, (uint256));
                if (actions[i].op == Operation.Repay) {
                    repay(position, actions[i].target, data); // Decrease position debt
                } else if (actions[i].op == Operation.Borrow) {
                    borrow(position, actions[i].target, data); // Increase position debt
                } else if (actions[i].op == Operation.AddAsset) {
                    IPosition(position).addAsset(actions[i].target); // Register position asset
                } else if (actions[i].op == Operation.RemoveAsset) {
                    IPosition(position).removeAsset(actions[i].target); // Deregister position asset
                } else if (actions[i].op == Operation.Deposit) {
                    IERC20(actions[i].target).safeTransferFrom(msg.sender, position, data); // Transfer assets to position
                } else {
                    revert InvalidOperation(); // Fallback revert
                }
            }
        }
        if (!RiskEngine(riskEngine).isPositionHealthy(position)) revert HealthCheckFailed();
    }

    function newPosition(address owner, uint256 positionType, bytes32 salt) internal returns (address) {
        if (beaconFor[positionType] == address(0)) revert InvalidOperation();
        address position = address(new BeaconProxy{salt: salt}(beaconFor[positionType], ""));
        ownerFor[position] = owner;
        auth[owner][position] = true;
        return position;
    }

    function repay(address position, address pool, uint256 _amt) internal {
        // to repay the entire debt set _amt to uint.max
        uint256 amt = (_amt == type(uint256).max) ? Pool(pool).getBorrowsOf(position) : _amt;

        IPosition(position).repay(Pool(pool).asset(), amt);
        Pool(pool).repay(position, amt);
    }

    function borrow(address position, address pool, uint256 amt) internal {
        IPosition(position).borrow(pool, amt);
        Pool(pool).borrow(position, amt);
    }

    struct DebtData {
        address pool;
        address asset;
        uint256 amt;
    }

    struct AssetData {
        address asset;
        uint256 amt;
    }

    function liquidate(address position, DebtData[] calldata debt, AssetData[] calldata collat) external {
        if (RiskEngine(riskEngine).isPositionHealthy(position)) revert InvalidOperation();
        for (uint256 i; i < debt.length; ++i) {
            IERC20(debt[i].asset).transferFrom(msg.sender, debt[i].pool, debt[i].amt);
            Pool(debt[i].pool).repay(position, debt[i].amt);
        }
        for (uint256 i; i < collat.length; ++i) {
            IPosition(position).transfer(msg.sender, collat[i].asset, collat[i].amt);
        }
        if (!RiskEngine(riskEngine).isPositionHealthy(position)) revert InvalidOperation();
    }

    // Admin Functions
    function setBeacon(uint256 positionType, address beacon) external onlyOwner {
        beaconFor[positionType] = beacon;
    }

    function setRiskEngine(address _riskEngine) external onlyOwner {
        riskEngine = _riskEngine;
    }
}
