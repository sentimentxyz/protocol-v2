// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import {Pool} from "./Pool.sol";
import {RiskEngine} from "./RiskEngine.sol";
import {PoolFactory} from "./PoolFactory.sol";
import {IPosition} from "./interface/IPosition.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// libraries
import {Errors} from "src/lib/Errors.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// contracts
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/*//////////////////////////////////////////////////////////////
                            Events
//////////////////////////////////////////////////////////////*/

event RiskEngineSet(address riskEngine);

event PoolFactorySet(address poolFactory);

event LiquidationFeeSet(uint256 liquidationFee);

event ContractSet(address indexed target, bool isAllowed);

event BeaconSet(uint256 indexed positionType, address beacon);

event AddAsset(address indexed position, address indexed caller, address asset);

event FunctionSet(address indexed target, bytes4 indexed method, bool isAllowed);

event RemoveAsset(address indexed position, address indexed caller, address asset);

event Liquidation(address indexed position, address indexed liquidator, address indexed owner);

event PositionDeployed(address indexed position, address indexed caller, address indexed owner);

event Repay(address indexed position, address indexed caller, address indexed pool, uint256 amount);

event Borrow(address indexed position, address indexed caller, address indexed pool, uint256 amount);

event Exec(address indexed position, address indexed caller, address indexed target, bytes4 functionSelector);

event Transfer(address indexed position, address indexed caller, address indexed target, address asset, uint256 amount);

event Approve(address indexed position, address indexed caller, address indexed spender, address asset, uint256 amount);

event Deposit(
    address indexed position, address indexed caller, address indexed depositor, address asset, uint256 amount
);

/*//////////////////////////////////////////////////////////////
                            Structs
//////////////////////////////////////////////////////////////*/

// data for position debt to be repaid by the liquidator
struct DebtData {
    // pool address for debt to be repaid
    address pool;
    // debt asset for pool, utility param to avoid calling pool.asset()
    address asset;
    // amount of debt to be repaid by the liqudiator
    // position manager assumes that this amount has already been approved
    uint256 amt;
}

// data for collateral assets to be received by the liquidator
struct AssetData {
    // token address
    address asset;
    // amount of collateral to be received by liquidator
    uint256 amt;
}

// defines various operation types that can be applied to a position
// every operation except NewPosition requires that the caller must be an authz caller or owner
enum Operation {
    NewPosition, // create2 a new position with a given type, no auth needed
    // the following operations require msg.sender to be authorized
    Exec, // execute arbitrary calldata on a position
    Deposit, // deposit collateral assets to a given position
    Transfer, // transfer assets from the position to a external address
    Approve, // allow a spender to transfer assets from a position
    Repay, // decrease position debt
    Borrow, // increase position debt
    AddAsset, // upsert collateral asset to position storage
    RemoveAsset // remove collateral asset from position storage

}

// loosely defined data struct to create a common data container for all operation types
// target and data are interpreted in different ways based on the operation type
struct Action {
    // operation type
    Operation op;
    // dynamic bytes data, interepreted differently across operation types
    bytes data;
}

/*//////////////////////////////////////////////////////////////
                        Position Manager
//////////////////////////////////////////////////////////////*/

contract PositionManager is ReentrancyGuardUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    /// @notice pool factory address
    /// @dev helps verify if a given pool was created by the pool factory
    PoolFactory public poolFactory;

    /// @notice risk engine address
    /// @dev used to check if a given position breaches risk thresholds
    RiskEngine public riskEngine;

    /// @notice liquidation fee in percentage, scaled by 18 decimals
    /// @dev accrued to the protocol on every liqudation
    uint256 public liquidationFee;

    // position => owner mapping
    /// @notice fetch owner for given position
    mapping(address position => address owner) public ownerOf;

    // position type => OZ UpgradeableBeacon
    /// @notice fetch beacon address for a given position type
    mapping(uint256 positionType => address beacon) public beaconFor;

    /// [caller][position] => [isAuthorized]
    /// @notice check if a given address is allowed to operate on a particular position
    /// @dev auth[x][y] stores if address x is authorized to operate on position y
    mapping(address position => mapping(address caller => bool isAuthz)) public isAuth;

    // defines the universe of approved contracts and methods that a position can interact with
    // mapping key -> first 20 bytes store the target address, next 4 bytes store the method selector
    mapping(address target => bool isAllowed) public isKnownContract;
    mapping(address target => mapping(bytes4 method => bool isAllowed)) public isKnownFunc;

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address _poolFactory, address _riskEngine, uint256 _liquidationFee) public initializer {
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        OwnableUpgradeable.__Ownable_init(msg.sender);
        PausableUpgradeable.__Pausable_init();

        poolFactory = PoolFactory(_poolFactory);
        riskEngine = RiskEngine(_riskEngine);
        liquidationFee = _liquidationFee;
    }

    /*//////////////////////////////////////////////////////////////
                          External Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice authorize a caller other than the owner to call process() on a position
    function toggleAuth(address user, address position) external {
        // only account owners are allowed to modify authorizations
        // disables transitive auth operations
        if (msg.sender != ownerOf[position]) revert Errors.OnlyPositionOwner();

        // update authz status in storage
        isAuth[position][user] = !isAuth[position][user];
    }

    /*//////////////////////////////////////////////////////////////
                         Position Interaction
    //////////////////////////////////////////////////////////////*/

    function process(address position, Action calldata action) external nonReentrant {
        _process(position, action);
        if (!riskEngine.isPositionHealthy(position)) revert Errors.HealthCheckFailed();
    }

    /// @notice procces a batch of actions on a given position
    /// @dev only one position can be operated on in one txn, including creation
    /// @param position the position to process the actions on
    /// @param actions the list of actions to process
    function processBatch(address position, Action[] calldata actions) external nonReentrant {
        // loop over actions and process them sequentially based on operation
        for (uint256 i; i < actions.length; ++i) {
            _process(position, actions[i]);
        }
        // after all the actions are processed, the position should be within risk thresholds
        if (!riskEngine.isPositionHealthy(position)) revert Errors.HealthCheckFailed();
    }

    /*//////////////////////////////////////////////////////////////
                          Internal Functions
    //////////////////////////////////////////////////////////////*/

    function _process(address position, Action calldata action) internal {
        if (action.op == Operation.NewPosition) {
            newPosition(position, action.data);
            return;
        }

        if (!isAuth[position][msg.sender]) revert Errors.UnauthorizedAction();

        if (action.op == Operation.Exec) {
            exec(position, action.data);
        } else if (action.op == Operation.Transfer) {
            transfer(position, action.data);
        } else if (action.op == Operation.Deposit) {
            deposit(position, action.data);
        } else if (action.op == Operation.Approve) {
            approve(position, action.data);
        } else if (action.op == Operation.Repay) {
            repay(position, action.data);
        } else if (action.op == Operation.Borrow) {
            borrow(position, action.data);
        } else if (action.op == Operation.AddAsset) {
            addAsset(position, action.data);
        } else if (action.op == Operation.RemoveAsset) {
            removeAsset(position, action.data);
        } else {
            revert Errors.UnknownOperation();
        }
    }

    /// @dev deterministically deploy a new beacon proxy representin a position
    /// @dev the target field in the action is the new owner of the position
    function newPosition(address predictedAddress, bytes calldata data) internal whenNotPaused {
        // positionType -> position type of new position to be deployed
        // owner -> owner to create the position on behalf of
        // salt -> create2 salt for position
        (address owner, uint256 positionType, bytes32 salt) = abi.decode(data, (address, uint256, bytes32));

        // revert if given position type doesn't have a register beacon
        if (beaconFor[positionType] == address(0)) revert Errors.NoPositionBeacon();

        // create2 a new position as a beacon proxy
        address position = address(new BeaconProxy{salt: salt}(beaconFor[positionType], ""));

        // update position owner
        ownerOf[position] = owner;

        // owner is authzd by default
        isAuth[position][owner] = true;

        if (position != predictedAddress) revert Errors.PositionAddressMismatch();

        emit PositionDeployed(position, msg.sender, owner);
    }

    function exec(address position, bytes calldata data) internal {
        // exec data is encodePacked (address, bytes)
        // target -> first 20 bytes, contract address to be called by the position
        // callData -> rest of the data, calldata to be executed on target
        address target = address(bytes20(data[:20]));
        if (!isKnownFunc[target][bytes4(data[20:24])]) revert Errors.UnknownExecCall();
        IPosition(position).exec(target, data[20:]);

        emit Exec(position, msg.sender, target, bytes4(data[20:24]));
    }

    function transfer(address position, bytes calldata data) internal {
        // recipient -> address that will receive the transferred tokens
        // asset -> address of token to be transferred
        // amt -> amount of asset to be transferred
        (address recipient, address asset, uint256 amt) = abi.decode(data, (address, address, uint256));
        IPosition(position).transfer(recipient, asset, amt);

        emit Transfer(position, msg.sender, recipient, asset, amt);
    }

    function deposit(address position, bytes calldata data) internal {
        // depositor -> address to transfer the tokens from, must have approval
        // asset -> address of token to be deposited
        // amt -> amount of asset to be deposited
        (address depositor, address asset, uint256 amt) = abi.decode(data, (address, address, uint256));
        IERC20(asset).safeTransferFrom(depositor, position, amt);

        emit Deposit(position, msg.sender, depositor, asset, amt);
    }

    function approve(address position, bytes calldata data) internal {
        // spender -> address to be approved
        // asset -> address of token to be approves
        // amt -> amount of asset to be approved
        (address spender, address asset, uint256 amt) = abi.decode(data, (address, address, uint256));
        if (!isKnownContract[asset]) revert Errors.UnknownContract();
        IPosition(position).approve(asset, spender, amt);

        emit Approve(position, msg.sender, spender, asset, amt);
    }

    /// @dev to repay the entire debt set _amt to uint.max
    function repay(address position, bytes calldata data) internal {
        // pool -> address of the pool that recieves the repaid debt
        // amt -> notional amount to be repaid

        (address pool, uint256 _amt) = abi.decode(data, (address, uint256));
        // if the passed amt is type(uint).max assume repayment of the entire debt
        uint256 amt = (_amt == type(uint256).max) ? Pool(pool).getBorrowsOf(position) : _amt;

        // transfer assets to be repaid from the position to the given pool
        // signals repayment to the position without making any changes in the pool
        // since every position is structured differently
        // we assume that any checks needed to validate repayment are implemented in the position
        IPosition(position).repay(pool, amt);

        // trigger pool repayment which assumes successful transfer of repaid assets
        Pool(pool).repay(position, amt);

        emit Repay(position, msg.sender, pool, amt);
    }

    function borrow(address position, bytes calldata data) internal whenNotPaused {
        // decode data
        // pool -> pool to borrow from
        // amt -> notional amount to be borrowed
        (address pool, uint256 amt) = abi.decode(data, (address, uint256));

        // revert if the given pool was not deployed by the protocol pool factory
        if (poolFactory.deployerFor(pool) == address(0)) revert Errors.UnknownPool();

        // signals a borrow operation without any actual transfer of borrowed assets
        // since every position type is structured differently
        // we assume that the position implements any checks needed to validate the borrow
        IPosition(position).borrow(pool, amt);

        // transfer borrowed assets from given pool to position
        // trigger pool borrow and increase debt owed by the position
        Pool(pool).borrow(position, amt);

        emit Borrow(position, msg.sender, pool, amt);
    }

    function addAsset(address position, bytes calldata data) internal whenNotPaused {
        // asset -> address of asset to be registered as collateral
        address asset = abi.decode(data, (address));

        // register asset as collateral
        // any position-specific validation must be done within the position contract
        IPosition(position).addAsset(asset);

        emit AddAsset(position, msg.sender, asset);
    }

    function removeAsset(address position, bytes calldata data) internal whenNotPaused {
        // asset -> address of asset to be deregistered as collateral
        address asset = abi.decode(data, (address));

        // deregister asset as collateral
        IPosition(position).removeAsset(asset);

        emit RemoveAsset(position, msg.sender, asset);
    }

    /*//////////////////////////////////////////////////////////////
                             Liquidation
    //////////////////////////////////////////////////////////////*/

    function liquidate(address position, DebtData[] calldata debt, AssetData[] calldata collat) external nonReentrant {
        // position must breach risk thresholds before liquidation
        if (riskEngine.isPositionHealthy(position)) revert Errors.LiquidateHealthyPosition();

        // verify that the liquidator seized by the liquidator is within bounds of the max
        // liquidation discount.
        if (!riskEngine.isValidLiquidation(position, debt, collat)) revert Errors.InvalidLiquidation();

        // sequentially repay position debts
        // assumes the position manager is approved to pull assets from the liquidator
        for (uint256 i; i < debt.length; ++i) {
            // transfer debt asset from the liquidator to the pool
            IERC20(debt[i].asset).transferFrom(msg.sender, debt[i].pool, debt[i].amt);

            // trigger pool repayment which assumes successful transfer of repaid assets
            Pool(debt[i].pool).repay(position, debt[i].amt);
        }

        // transfer position assets to the liqudiator and accrue protocol liquidation fees
        for (uint256 i; i < collat.length; ++i) {
            // compute fee amt
            uint256 fee = liquidationFee.mulDiv(collat[i].amt, 1e18);

            // transfer fee amt to protocol
            IPosition(position).transfer(owner(), collat[i].asset, fee);

            // transfer difference to the liquidator
            IPosition(position).transfer(msg.sender, collat[i].asset, collat[i].amt - fee);
        }

        // position should be within risk thresholds after liqudiation
        if (!riskEngine.isPositionHealthy(position)) revert Errors.HealthCheckFailed();

        emit Liquidation(position, msg.sender, ownerOf[position]);
    }

    /*//////////////////////////////////////////////////////////////
                              Only Owner
    //////////////////////////////////////////////////////////////*/

    /// @notice update the beacon for a given position type
    /// @dev only callable by the position manager owner
    function setBeacon(uint256 positionType, address beacon) external onlyOwner {
        beaconFor[positionType] = beacon;

        emit BeaconSet(positionType, beacon);
    }

    /// @notice update the risk engine address
    /// @dev only callable by the position manager owner
    function setRiskEngine(address _riskEngine) external onlyOwner {
        riskEngine = RiskEngine(_riskEngine);

        emit RiskEngineSet(_riskEngine);
    }

    /// @notice update the pool factory address
    /// @dev only callable by the position manager owner
    function setPoolFactory(address _poolFactory) external onlyOwner {
        poolFactory = PoolFactory(_poolFactory);

        emit PoolFactorySet(_poolFactory);
    }

    /// @notice update the protocol liqudiation fee
    /// @dev only callable by the position manager owner
    function setLiquidationFee(uint256 _liquidationFee) external onlyOwner {
        liquidationFee = _liquidationFee;

        emit LiquidationFeeSet(_liquidationFee);
    }

    /// @notice toggle contract inclusion in the contract universe
    /// @dev only callable by the position manager owner
    function toggleKnownContract(address target) external onlyOwner {
        isKnownContract[target] = !isKnownContract[target];

        emit ContractSet(target, isKnownContract[target]);
    }

    /// @notice toggle function inclusion in the function universe
    /// @dev only callable by the position manager owner
    function toggleKnownFunc(address target, bytes4 method) external onlyOwner {
        isKnownFunc[target][method] = !isKnownFunc[target][method];

        emit FunctionSet(target, method, isKnownFunc[target][method]);
    }
}
