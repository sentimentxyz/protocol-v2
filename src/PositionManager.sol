// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import {Pool} from "./Pool.sol";
import {Registry} from "./Registry.sol";
import {Position} from "./Position.sol";
import {RiskEngine} from "./RiskEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// contracts
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/*//////////////////////////////////////////////////////////////
                            Structs
//////////////////////////////////////////////////////////////*/

// data for position debt to be repaid by the liquidator
struct DebtData {
    // poolId address for debt to be repaid
    uint256 poolId;
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
    Deposit, // Add collateral to a given position
    Transfer, // transfer assets from the position to a external address
    Approve, // allow a spender to transfer assets from a position
    Repay, // decrease position debt
    Borrow, // increase position debt
    AddToken, // upsert collateral asset to position storage
    RemoveToken // remove collateral asset from position storage

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

    // keccak(SENTIMENT_POOL_KEY)
    bytes32 public constant SENTIMENT_POOL_KEY = 0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728;
    // keccak(SENTIMENT_RISK_ENGINE_KEY)
    bytes32 public constant SENTIMENT_RISK_ENGINE_KEY =
        0x5b6696788621a5d6b5e3b02a69896b9dd824ebf1631584f038a393c29b6d7555;
    // keccak(SENIMENT_POSITION_BEACON_KEY)
    bytes32 public constant SENTIMENT_POSITION_BEACON_KEY =
        0xc77ea3242ed8f193508dbbe062eaeef25819b43b511cbe2fc5bd5de7e23b9990;

    Registry public registry;

    Pool public pool;

    /// @notice risk engine address
    /// @dev used to check if a given position breaches risk thresholds
    RiskEngine public riskEngine;

    address public positionBeacon;

    /// @notice liquidation fee in percentage, scaled by 18 decimals
    /// @dev accrued to the protocol on every liqudation
    uint256 public liquidationFee;

    // position => owner mapping
    /// @notice fetch owner for given position
    mapping(address position => address owner) public ownerOf;

    /// [caller][position] => [isAuthorized]
    /// @notice check if a given address is allowed to operate on a particular position
    /// @dev auth[x][y] stores if address x is authorized to operate on position y
    mapping(address position => mapping(address caller => bool isAuthz)) public isAuth;

    // defines the universe of approved contracts and methods that a position can interact with
    // mapping key -> first 20 bytes store the target address, next 4 bytes store the method selector
    mapping(address target => bool isAllowed) public isKnownAddress;
    mapping(address target => mapping(bytes4 method => bool isAllowed)) public isKnownFunc;

    /*//////////////////////////////////////////////////////////////
                            Events
    //////////////////////////////////////////////////////////////*/

    event BeaconSet(address beacon);
    event RiskEngineSet(address riskEngine);
    event PoolFactorySet(address poolFactory);
    event LiquidationFeeSet(uint256 liquidationFee);
    event AddressSet(address indexed target, bool isAllowed);
    event AddToken(address indexed position, address indexed caller, address asset);
    event FunctionSet(address indexed target, bytes4 indexed method, bool isAllowed);
    event RemoveToken(address indexed position, address indexed caller, address asset);
    event Liquidation(address indexed position, address indexed liquidator, address indexed owner);
    event PositionDeployed(address indexed position, address indexed caller, address indexed owner);
    event Deposit(address indexed position, address indexed depositor, address asset, uint256 amount);
    event Repay(address indexed position, address indexed caller, uint256 indexed poolId, uint256 amount);
    event Borrow(address indexed position, address indexed caller, uint256 indexed poolId, uint256 amount);
    event Exec(address indexed position, address indexed caller, address indexed target, bytes4 functionSelector);
    event Transfer(
        address indexed position, address indexed caller, address indexed target, address asset, uint256 amount
    );
    event Approve(
        address indexed position, address indexed caller, address indexed spender, address asset, uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/
    error PositionManager_NoPositionBeacon();
    error PositionManager_UnknownPool(uint256 poolId);
    error PositionManager_UnknownSpender(address spender);
    error PositionManager_UnknownContract(address target);
    error PositionManager_UnknownOperation(uint256 operation);
    error PositionManager_HealthCheckFailed(address position);
    error PositionManager_InvalidLiquidation(address position);
    error PositionManager_LiquidateHealthyPosition(address position);
    error PositionManager_InvalidDebtData(address asset, address poolAsset);
    error PositionManager_OnlyPositionOwner(address position, address sender);
    error PositionManager_UnknownFuncSelector(address target, bytes4 selector);
    error PositionManager_OnlyPositionAuthorized(address position, address sender);
    error PositionManager_PredictedPositionMismatch(address position, address predicted);

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address _registry, uint256 _liquidationFee) public initializer {
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        OwnableUpgradeable.__Ownable_init(msg.sender);
        PausableUpgradeable.__Pausable_init();

        registry = Registry(_registry);
        liquidationFee = _liquidationFee;
    }

    function updateFromRegistry() external {
        pool = Pool(registry.addressFor(SENTIMENT_POOL_KEY));
        riskEngine = RiskEngine(registry.addressFor(SENTIMENT_RISK_ENGINE_KEY));
        positionBeacon = registry.addressFor(SENTIMENT_POSITION_BEACON_KEY);
    }

    /*//////////////////////////////////////////////////////////////
                          External Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice authorize a caller other than the owner to call process() on a position
    function toggleAuth(address user, address position) external {
        // only account owners are allowed to modify authorizations
        // disables transitive auth operations
        if (msg.sender != ownerOf[position]) revert PositionManager_OnlyPositionOwner(position, msg.sender);

        // update authz status in storage
        isAuth[position][user] = !isAuth[position][user];
    }

    /*//////////////////////////////////////////////////////////////
                         Position Interaction
    //////////////////////////////////////////////////////////////*/

    function process(address position, Action calldata action) external nonReentrant {
        _process(position, action);
        if (!riskEngine.isPositionHealthy(position)) revert PositionManager_HealthCheckFailed(position);
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
        if (!riskEngine.isPositionHealthy(position)) revert PositionManager_HealthCheckFailed(position);
    }

    /*//////////////////////////////////////////////////////////////
                          Internal Functions
    //////////////////////////////////////////////////////////////*/

    function _process(address position, Action calldata action) internal {
        if (action.op == Operation.NewPosition) {
            newPosition(position, action.data);
            return;
        }

        if (!isAuth[position][msg.sender]) revert PositionManager_OnlyPositionAuthorized(position, msg.sender);

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
        } else if (action.op == Operation.AddToken) {
            addToken(position, action.data);
        } else if (action.op == Operation.RemoveToken) {
            removeToken(position, action.data);
        } else {
            revert PositionManager_UnknownOperation(uint256(action.op));
        }
    }

    /// @dev deterministically deploy a new beacon proxy representin a position
    /// @dev the target field in the action is the new owner of the position
    function newPosition(address predictedAddress, bytes calldata data) internal whenNotPaused {
        // positionType -> position type of new position to be deployed
        // owner -> owner to create the position on behalf of
        // salt -> create2 salt for position
        (address owner, bytes32 salt) = abi.decode(data, (address, bytes32));

        // hash salt with owner to mitigate position creations being frontrun
        salt = keccak256(abi.encodePacked(owner, salt));

        // create2 a new position as a beacon proxy
        address position = address(new BeaconProxy{salt: salt}(positionBeacon, ""));

        // update position owner
        ownerOf[position] = owner;

        // owner is authzd by default
        isAuth[position][owner] = true;

        if (position != predictedAddress) revert PositionManager_PredictedPositionMismatch(position, predictedAddress);

        emit PositionDeployed(position, msg.sender, owner);
    }

    function exec(address position, bytes calldata data) internal {
        // exec data is encodePacked (address, bytes)
        // target -> first 20 bytes, contract address to be called by the position
        // callData -> rest of the data, calldata to be executed on target
        address target = address(bytes20(data[:20]));
        if (!isKnownFunc[target][bytes4(data[20:24])]) {
            revert PositionManager_UnknownFuncSelector(target, bytes4(data[20:24]));
        }
        Position(position).exec(target, data[20:]);

        emit Exec(position, msg.sender, target, bytes4(data[20:24]));
    }

    function transfer(address position, bytes calldata data) internal {
        // recipient -> address that will receive the transferred tokens
        // asset -> address of token to be transferred
        // amt -> amount of asset to be transferred
        (address recipient, address asset, uint256 amt) = abi.decode(data, (address, address, uint256));
        if (!isKnownAddress[asset]) revert PositionManager_UnknownContract(asset);
        Position(position).transfer(recipient, asset, amt);

        emit Transfer(position, msg.sender, recipient, asset, amt);
    }

    function deposit(address position, bytes calldata data) internal {
        // depositor -> address to transfer the tokens from, must have approval
        // asset -> address of token to be deposited
        // amt -> amount of asset to be deposited
        (address asset, uint256 amt) = abi.decode(data, (address, uint256));
        IERC20(asset).safeTransferFrom(msg.sender, position, amt);

        emit Deposit(position, msg.sender, asset, amt);
    }

    function approve(address position, bytes calldata data) internal {
        // spender -> address to be approved
        // asset -> address of token to be approves
        // amt -> amount of asset to be approved
        (address spender, address asset, uint256 amt) = abi.decode(data, (address, address, uint256));
        if (!isKnownAddress[asset]) revert PositionManager_UnknownContract(asset);
        if (!isKnownAddress[spender]) revert PositionManager_UnknownSpender(spender);
        Position(position).approve(asset, spender, amt);

        emit Approve(position, msg.sender, spender, asset, amt);
    }

    /// @dev to repay the entire debt set _amt to uint.max
    function repay(address position, bytes calldata data) internal {
        // poolId -> pool that recieves the repaid debt
        // amt -> notional amount to be repaid

        (uint256 poolId, uint256 _amt) = abi.decode(data, (uint256, uint256));
        // if the passed amt is type(uint).max assume repayment of the entire debt
        uint256 amt = (_amt == type(uint256).max) ? pool.getBorrowsOf(poolId, position) : _amt;

        // signals repayment to the position without making any changes in the pool
        // since every position is structured differently
        // we assume that any checks needed to validate repayment are implemented in the position
        Position(position).repay(poolId, amt);

        // transfer assets to be repaid from the position to the given pool
        Position(position).transfer(address(pool), pool.getPoolAssetFor(poolId), amt);

        // trigger pool repayment which assumes successful transfer of repaid assets
        pool.repay(poolId, position, amt);

        // signals repayment to the position without making any changes in the pool
        // since every position is structured differently
        // we assume that any checks needed to validate repayment are implemented in the position
        Position(position).repay(poolId, amt);

        emit Repay(position, msg.sender, poolId, amt);
    }

    function borrow(address position, bytes calldata data) internal whenNotPaused {
        // decode data
        // poolId -> pool to borrow from
        // amt -> notional amount to be borrowed
        (uint256 poolId, uint256 amt) = abi.decode(data, (uint256, uint256));

        // revert if the given pool was not deployed by the protocol pool factory
        if (pool.ownerOf(poolId) == address(0)) revert PositionManager_UnknownPool(poolId);

        // signals a borrow operation without any actual transfer of borrowed assets
        // since every position type is structured differently
        // we assume that the position implements any checks needed to validate the borrow
        Position(position).borrow(poolId, amt);

        // transfer borrowed assets from given pool to position
        // trigger pool borrow and increase debt owed by the position
        pool.borrow(poolId, position, amt);

        emit Borrow(position, msg.sender, poolId, amt);
    }

    function addToken(address position, bytes calldata data) internal whenNotPaused {
        // asset -> address of asset to be registered as collateral
        address asset = abi.decode(data, (address));

        // register asset as collateral
        // any position-specific validation must be done within the position contract
        Position(position).addCollateralType(asset);

        emit AddToken(position, msg.sender, asset);
    }

    function removeToken(address position, bytes calldata data) internal whenNotPaused {
        // asset -> address of asset to be deregistered as collateral
        address asset = abi.decode(data, (address));

        // deregister asset as collateral
        Position(position).removeCollateralType(asset);

        emit RemoveToken(position, msg.sender, asset);
    }

    /*//////////////////////////////////////////////////////////////
                             Liquidation
    //////////////////////////////////////////////////////////////*/

    function liquidate(address position, DebtData[] calldata debt, AssetData[] calldata collat) external nonReentrant {
        // position must breach risk thresholds before liquidation
        if (riskEngine.isPositionHealthy(position)) revert PositionManager_LiquidateHealthyPosition(position);

        // verify that the liquidator seized by the liquidator is within liquidiation discount
        riskEngine.validateLiquidation(debt, collat);

        // sequentially repay position debts
        // assumes the position manager is approved to pull assets from the liquidator
        for (uint256 i; i < debt.length; ++i) {
            // verify that the asset being repaid is actually the pool asset
            if (debt[i].asset != pool.getPoolAssetFor(debt[i].poolId)) {
                revert PositionManager_InvalidDebtData(debt[i].asset, pool.getPoolAssetFor(debt[i].poolId));
            }

            // transfer debt asset from the liquidator to the pool
            IERC20(debt[i].asset).transferFrom(msg.sender, address(pool), debt[i].amt);

            // trigger pool repayment which assumes successful transfer of repaid assets
            pool.repay(debt[i].poolId, position, debt[i].amt);

            // update position to reflect repayment of debt by liquidator
            Position(position).repay(debt[i].poolId, debt[i].amt);
        }

        // transfer position assets to the liqudiator and accrue protocol liquidation fees
        for (uint256 i; i < collat.length; ++i) {
            // compute fee amt
            // [ROUND] liquidation fee is rounded down, in favor of the liquidator
            uint256 fee = liquidationFee.mulDiv(collat[i].amt, 1e18);

            // transfer fee amt to protocol
            Position(position).transfer(owner(), collat[i].asset, fee);

            // transfer difference to the liquidator
            Position(position).transfer(msg.sender, collat[i].asset, collat[i].amt - fee);
        }

        // position should be within risk thresholds after liqudiation
        if (!riskEngine.isPositionHealthy(position)) revert PositionManager_HealthCheckFailed(position);

        emit Liquidation(position, msg.sender, ownerOf[position]);
    }

    /*//////////////////////////////////////////////////////////////
                              Only Owner
    //////////////////////////////////////////////////////////////*/

    /// @notice update the beacon for a given position type
    /// @dev only callable by the position manager owner
    function setBeacon(address _positionBeacon) external onlyOwner {
        positionBeacon = _positionBeacon;

        emit BeaconSet(_positionBeacon);
    }

    /// @notice update the risk engine address
    /// @dev only callable by the position manager owner
    function setRiskEngine(address _riskEngine) external onlyOwner {
        riskEngine = RiskEngine(_riskEngine);

        emit RiskEngineSet(_riskEngine);
    }

    /// @notice update the protocol liqudiation fee
    /// @dev only callable by the position manager owner
    function setLiquidationFee(uint256 _liquidationFee) external onlyOwner {
        liquidationFee = _liquidationFee;

        emit LiquidationFeeSet(_liquidationFee);
    }

    /// @notice toggle contract inclusion in the contract universe
    /// @dev only callable by the position manager owner
    function toggleKnownAddress(address target) external onlyOwner {
        isKnownAddress[target] = !isKnownAddress[target];

        emit AddressSet(target, isKnownAddress[target]);
    }

    /// @notice toggle function inclusion in the function universe
    /// @dev only callable by the position manager owner
    function toggleKnownFunc(address target, bytes4 method) external onlyOwner {
        isKnownFunc[target][method] = !isKnownFunc[target][method];

        emit FunctionSet(target, method, isKnownFunc[target][method]);
    }
}
