// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        Position Manager
//////////////////////////////////////////////////////////////*/

// types
import {Pool} from "src/Pool.sol";
import {PositionManager} from "src/PositionManager.sol";
import {Position} from "src/Position.sol";
import {Registry} from "src/Registry.sol";
import {RiskEngine} from "src/RiskEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// contracts
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/// @title PositionManager
/// @notice Handles the deployment and use of Positions against the Singleton Pool Contract
contract MockPositionManager is PositionManager {
    using Math for uint256;
    using SafeERC20 for IERC20;

    mapping(address => address[]) public positionsOf;

    function setPositionsOf(address user, address position) external {
        positionsOf[user].push(position);
    }

    function positionsLength(address user) external view returns (uint256) {
        return positionsOf[user].length;
    }
}
