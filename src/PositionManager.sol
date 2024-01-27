// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// types
import {Pool} from "./Pool.sol";
import {RiskEngine} from "./RiskEngine.sol";
import {PoolFactory} from "./PoolFactory.sol";
import {IPosition} from "./interfaces/IPosition.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// contracts
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract PositionManager is ReentrancyGuardUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    error InvalidPool();
    error Unauthorized();
    error InvalidOperation();
    error HealthCheckFailed();
    error InvalidPositionType();

    RiskEngine public riskEngine;
    uint256 public liquidationFee;
    PoolFactory public poolFactory;

    mapping(address position => address owner) public ownerOf; // position => owner mapping
    mapping(uint256 positionType => address beacon) public beaconFor; // type => UpgradeableBeacon

    /// @dev auth[x][y] stores if address x is authorized to operate on position y
    mapping(address caller => mapping(address position => bool isAuthz)) public auth;

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        OwnableUpgradeable.__Ownable_init(msg.sender);
        PausableUpgradeable.__Pausable_init();
    }

    /// @notice allow other addresses to call process() on behalf of the position owner
    function setAuth(address user, address position, bool isAuthorized) external {
        if (msg.sender != ownerOf[position]) revert Unauthorized();
        auth[user][position] = isAuthorized;
    }

    enum Operation {
        Repay, // decrease position debt
        Borrow, // increase position debt
        Deposit, // send assets to the position
        Exec, // interact with an external contract
        Transfer, // transfer assets from the position
        NewPosition, // deploy and create a new position
        AddAsset, // upsert collateral asset to position storage
        RemoveAsset // delete collateral asset from position storage
    }

    struct Action {
        Operation op;
        address target;
        bytes data;
    }

    function process(address position, Action[] calldata actions) external nonReentrant {
        for (uint256 i; i < actions.length; ++i) {
            // new position creation need not be authzd
            if (actions[i].op == Operation.NewPosition) {
                (uint256 positionType, bytes32 salt) = abi.decode(actions[i].data, (uint256, bytes32));
                if (ownerOf[position] != address(0)) revert InvalidOperation();
                if (position != newPosition(actions[i].target, positionType, salt)) revert InvalidOperation();
                continue;
            }

            if (!auth[msg.sender][position]) revert Unauthorized();

            if (actions[i].op == Operation.Exec) {
                // target -> contract address to be called by the position
                // data -> abi-encoded calldata to be passed
                IPosition(position).exec(actions[i].target, actions[i].data);
            } else if (actions[i].op == Operation.Transfer) {
                // target -> address to transfer assets to
                // data -> asset to be transferred and amount
                (address asset, uint256 amt) = abi.decode(actions[i].data, (address, uint256));
                IPosition(position).transfer(actions[i].target, asset, amt);
            } else if (actions[i].op == Operation.Deposit) {
                // target -> depositor address
                // data -> asset to be transferred and amount
                (address asset, uint256 amt) = abi.decode(actions[i].data, (address, uint256));
                IERC20(asset).safeTransferFrom(actions[i].target, position, amt);
            } else {
                uint256 data = abi.decode(actions[i].data, (uint256));
                if (actions[i].op == Operation.Repay) {
                    // target -> pool to be repaid
                    // data -> notional amount to be repaid
                    repay(position, actions[i].target, data);
                } else if (actions[i].op == Operation.Borrow) {
                    // target -> pool to borrow from
                    // amt -> notional amount to be borrowed
                    borrow(position, actions[i].target, data);
                } else if (actions[i].op == Operation.AddAsset) {
                    // target -> asset to be registered as collateral
                    // data is ignored
                    IPosition(position).addAsset(actions[i].target);
                } else if (actions[i].op == Operation.RemoveAsset) {
                    // target -> asset to be deregistered as collateral
                    // data is ignored
                    IPosition(position).removeAsset(actions[i].target);
                } else {
                    revert InvalidOperation(); // Fallback revert
                }
            }
        }
        if (!riskEngine.isPositionHealthy(position)) revert HealthCheckFailed();
    }

    /// @notice deterministically deploy a new beacon proxy position
    function newPosition(address owner, uint256 positionType, bytes32 salt) internal returns (address) {
        if (beaconFor[positionType] == address(0)) revert InvalidPositionType();
        address position = address(new BeaconProxy{salt: salt}(beaconFor[positionType], ""));
        ownerOf[position] = owner;
        auth[owner][position] = true;
        return position;
    }

    /// @dev to repay the entire debt set _amt to uint.max
    function repay(address position, address pool, uint256 _amt) internal {
        uint256 amt = (_amt == type(uint256).max) ? Pool(pool).getBorrowsOf(position) : _amt;
        IPosition(position).repay(Pool(pool).asset(), amt);
        Pool(pool).repay(position, amt);
    }

    function borrow(address position, address pool, uint256 amt) internal {
        if (poolFactory.managerFor(pool) == address(0)) revert InvalidPool();
        IPosition(position).borrow(pool, amt); // this must check if borrow is valid
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

    function liquidate(address position, DebtData[] calldata debt, AssetData[] calldata collat) external nonReentrant {
        if (riskEngine.isPositionHealthy(position)) revert InvalidOperation();
        for (uint256 i; i < debt.length; ++i) {
            IERC20(debt[i].asset).transferFrom(msg.sender, debt[i].pool, debt[i].amt);
            Pool(debt[i].pool).repay(position, debt[i].amt);
        }
        for (uint256 i; i < collat.length; ++i) {
            uint256 fee = liquidationFee.mulDiv(1e18, collat[i].amt);
            IPosition(position).transfer(owner(), collat[i].asset, fee);
            IPosition(position).transfer(msg.sender, collat[i].asset, collat[i].amt - fee);
        }
        if (!riskEngine.isPositionHealthy(position)) revert InvalidOperation();
        // TODO emit liquidation event and/or reset position
    }

    // Admin Functions
    function setBeacon(uint256 positionType, address beacon) external onlyOwner {
        beaconFor[positionType] = beacon;
    }

    function setRiskEngine(address _riskEngine) external onlyOwner {
        riskEngine = RiskEngine(_riskEngine);
    }

    function setPoolFactory(address _poolFactory) external onlyOwner {
        poolFactory = PoolFactory(_poolFactory);
    }

    function setLiquidationFee(uint256 _liquidationFee) external onlyOwner {
        liquidationFee = _liquidationFee;
    }
}
