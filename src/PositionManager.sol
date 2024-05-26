// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        Position Manager
//////////////////////////////////////////////////////////////*/

// types
import { Pool } from "./Pool.sol";
import { Registry } from "./Registry.sol";
import { Position } from "./Position.sol";
import { RiskEngine } from "./RiskEngine.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// libraries
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// contracts
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// data for position debt to be repaid by the liquidator
struct DebtData {
    // poolId address for debt to be repaid
    uint256 poolId;
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

/// @title PositionManager
/// @notice Handles the deployment and use of Positions against the Singleton Pool Contract
contract PositionManager is ReentrancyGuardUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    // keccak(SENTIMENT_POOL_KEY)
    bytes32 public constant SENTIMENT_POOL_KEY = 0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728;
    // keccak(SENTIMENT_RISK_ENGINE_KEY)
    bytes32 public constant SENTIMENT_RISK_ENGINE_KEY = 0x5b6696788621a5d6b5e3b02a69896b9dd824ebf1631584f038a393c29b6d7555;
    // keccak(SENIMENT_POSITION_BEACON_KEY)
    bytes32 public constant SENTIMENT_POSITION_BEACON_KEY = 0xc77ea3242ed8f193508dbbe062eaeef25819b43b511cbe2fc5bd5de7e23b9990;

    /// @notice Sentiment Singleton Pool
    Pool public pool;
    /// @notice Sentiment Registry
    Registry public registry;
    /// @notice Sentiment Risk Engine
    RiskEngine public riskEngine;
    /// @notice Position Beacon
    address public positionBeacon;

    /// @notice Liquidation fee in percentage, scaled by 18 decimals
    /// @dev accrued to the protocol on every liqudation
    uint256 public liquidationFee;

    /// @notice Fetch owner for given position
    mapping(address position => address owner) public ownerOf;

    /// @notice Check if a given address is allowed to operate on a particular position
    /// @dev [caller][position] => [isAuthorized] stores if caller is authorized to operate on position
    mapping(address position => mapping(address caller => bool isAuthz)) public isAuth;

    // universe mappings:
    // the following two mappings define the universe of the protocol. this is used to define a
    // subset of the network that a position can freely interact with. isKnownAddress defines
    // recognized addresses. these include assets that a position interacts with and addresses that
    // can approved as spenders' for assets in a position. isKnownFunc defines the exec universe
    // for a function by creating a mapping of particular target-function pairs that can be called
    // by a position.

    /// @notice Check if a given address is recognized by the protocol
    mapping(address target => bool isAllowed) public isKnownAddress;
    /// @notice Check if a position can interact with a given target-function pair
    mapping(address target => mapping(bytes4 method => bool isAllowed)) public isKnownFunc;

    /// @notice Position Beacon address was updated
    event BeaconSet(address beacon);
    /// @notice Protocol registry address was updated
    event RegistrySet(address registry);
    /// @notice Protocol liquidation fee was updated
    event LiquidationFeeSet(uint256 liquidationFee);
    /// @notice Known state of an address was toggled
    event ToggleKnownAddress(address indexed target, bool isAllowed);
    /// @notice Token was added to a position's asset list
    event AddToken(address indexed position, address indexed caller, address asset);
    /// @notice Known state of a target-function pair was toggled
    event ToggleKnownFunc(address indexed target, bytes4 indexed method, bool isAllowed);
    /// @notice Token was removed from a position's asset list
    event RemoveToken(address indexed position, address indexed caller, address asset);
    /// @notice Position was successfully liquidated
    event Liquidation(address indexed position, address indexed liquidator, address indexed owner);
    /// @notice New position was deployed
    event PositionDeployed(address indexed position, address indexed caller, address indexed owner);
    /// @notice Assets were deposited to a position
    event Deposit(address indexed position, address indexed depositor, address asset, uint256 amount);
    /// @notice Debt was repaid from a position to a pool
    event Repay(address indexed position, address indexed caller, uint256 indexed poolId, uint256 amount);
    /// @notice Assets were borrowed from a pool to a position
    event Borrow(address indexed position, address indexed caller, uint256 indexed poolId, uint256 amount);
    /// @notice An external operation was executed on a position
    event Exec(address indexed position, address indexed caller, address indexed target, bytes4 functionSelector);
    /// @notice Assets were transferred out of a position
    event Transfer(address indexed position, address indexed caller, address indexed target, address asset, uint256 amount);
    /// @notice Approval was granted for assets belonging to a position
    event Approve(address indexed position, address indexed caller, address indexed spender, address asset, uint256 amount);

    /// @notice The pool a position is trying to borrow from does not exist
    error PositionManager_UnknownPool(uint256 poolId);
    /// @notice Unknown spenders cannot be granted approval to position assets
    error PositionManager_UnknownSpender(address spender);
    /// @notice Position cannot interact with unknown contracts
    error PositionManager_UnknownContract(address target);
    /// @notice Position health check failed
    error PositionManager_HealthCheckFailed(address position);
    /// @notice Cannot liquidate healthy position
    error PositionManager_LiquidateHealthyPosition(address position);
    /// @notice Attempt to deposit zero assets to a position
    error PositionManager_ZeroAmountDeposit(address position, address asset);
    /// @notice Function access restricted to position owner only
    error PositionManager_OnlyPositionOwner(address position, address sender);
    /// @notice Unknown target-function selector pair
    error PositionManager_UnknownFuncSelector(address target, bytes4 selector);
    /// @notice Function access restricted to authorozied addresses
    error PositionManager_OnlyPositionAuthorized(address position, address sender);
    /// @notice Predicted position address does not match with deployed address
    error PositionManager_PredictedPositionMismatch(address position, address predicted);

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer for TransparentUpgradeableProxy
    /// @param registry_ Sentiment Registry
    /// @param liquidationFee_ Protocol liquidation fee
    function initialize(address registry_, uint256 liquidationFee_) public initializer {
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        OwnableUpgradeable.__Ownable_init(msg.sender);
        PausableUpgradeable.__Pausable_init();
        registry = Registry(registry_);
        liquidationFee = liquidationFee_;
    }

    /// @notice Fetch and update module addreses from the registry
    function updateFromRegistry() external {
        pool = Pool(registry.addressFor(SENTIMENT_POOL_KEY));
        riskEngine = RiskEngine(registry.addressFor(SENTIMENT_RISK_ENGINE_KEY));
        positionBeacon = registry.addressFor(SENTIMENT_POSITION_BEACON_KEY);
    }

    /// @notice Authorize a caller other than the owner to operate on a position
    function toggleAuth(address user, address position) external {
        // only account owners are allowed to modify authorizations
        // disables transitive auth operations
        if (msg.sender != ownerOf[position]) revert PositionManager_OnlyPositionOwner(position, msg.sender);

        // update authz status in storage
        isAuth[position][user] = !isAuth[position][user];
    }

    /// @notice Process a single action on a given position
    /// @param position Position address
    /// @param action Action config
    function process(address position, Action calldata action) external nonReentrant {
        _process(position, action);
        if (!riskEngine.isPositionHealthy(position)) revert PositionManager_HealthCheckFailed(position);
    }

    /// @notice Procces a batch of actions on a given position
    /// @dev only one position can be operated on in one txn, including creation
    /// @param position Position address
    /// @param actions List of actions to process
    function processBatch(address position, Action[] calldata actions) external nonReentrant {
        // loop over actions and process them sequentially based on operation
        for (uint256 i; i < actions.length; ++i) {
            _process(position, actions[i]);
        }
        // after all the actions are processed, the position should be within risk thresholds
        if (!riskEngine.isPositionHealthy(position)) revert PositionManager_HealthCheckFailed(position);
    }

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
        }
    }

    /// @dev deterministically deploy a new beacon proxy representing a position
    /// @dev the target field in the action is the new owner of the position
    function newPosition(address predictedAddress, bytes calldata data) internal whenNotPaused {
        // positionType -> position type of new position to be deployed
        // owner -> owner to create the position on behalf of
        // salt -> create2 salt for position
        (address owner, bytes32 salt) = abi.decode(data, (address, bytes32));

        // hash salt with owner to mitigate position creations being frontrun
        salt = keccak256(abi.encodePacked(owner, salt));

        // create2 a new position as a beacon proxy
        address position = address(new BeaconProxy{ salt: salt }(positionBeacon, ""));

        // update position owner
        ownerOf[position] = owner;

        // owner is authzd by default
        isAuth[position][owner] = true;

        if (position != predictedAddress) revert PositionManager_PredictedPositionMismatch(position, predictedAddress);

        emit PositionDeployed(position, msg.sender, owner);
    }

    /// @dev Operate on a position by interaction with external contracts using arbitrary calldata
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

    /// @dev Transfer assets out of a position
    function transfer(address position, bytes calldata data) internal {
        // recipient -> address that will receive the transferred tokens
        // asset -> address of token to be transferred
        // amt -> amount of asset to be transferred
        (address recipient, address asset, uint256 amt) = abi.decode(data, (address, address, uint256));
        if (!isKnownAddress[asset]) revert PositionManager_UnknownContract(asset);
        Position(position).transfer(recipient, asset, amt);

        emit Transfer(position, msg.sender, recipient, asset, amt);
    }

    /// @dev Deposit assets from msg.sender to a position
    function deposit(address position, bytes calldata data) internal {
        // depositor -> address to transfer the tokens from, must have approval
        // asset -> address of token to be deposited
        // amt -> amount of asset to be deposited
        (address asset, uint256 amt) = abi.decode(data, (address, uint256));
        IERC20(asset).safeTransferFrom(msg.sender, position, amt);
        if (amt == 0) revert PositionManager_ZeroAmountDeposit(position, asset);
        emit Deposit(position, msg.sender, asset, amt);
    }

    /// @dev Approve a spender to use assets from a position
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

    /// @dev Decrease position debt via repayment. To repay the entire debt set `_amt` to uint.max
    function repay(address position, bytes calldata data) internal {
        // poolId -> pool that recieves the repaid debt
        // amt -> notional amount to be repaid

        (uint256 poolId, uint256 _amt) = abi.decode(data, (uint256, uint256));
        // if the passed amt is type(uint).max assume repayment of the entire debt
        uint256 amt = (_amt == type(uint256).max) ? pool.getBorrowsOf(poolId, position) : _amt;

        // transfer assets to be repaid from the position to the given pool
        Position(position).transfer(address(pool), pool.getPoolAssetFor(poolId), amt);

        // trigger pool repayment which assumes successful transfer of repaid assets
        pool.repay(poolId, position, amt);

        // signals repayment to the position without making any changes in the pool
        // any checks needed to validate repayment must be implemented in the position
        Position(position).repay(poolId, amt);

        emit Repay(position, msg.sender, poolId, amt);
    }

    /// @dev Increase position debt via borrowing
    function borrow(address position, bytes calldata data) internal whenNotPaused {
        // decode data
        // poolId -> pool to borrow from
        // amt -> notional amount to be borrowed
        (uint256 poolId, uint256 amt) = abi.decode(data, (uint256, uint256));

        // revert if the given pool does not exist
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

    /// @dev Add a token address to the set of position assets
    function addToken(address position, bytes calldata data) internal whenNotPaused {
        // asset -> address of asset to be registered as collateral
        address asset = abi.decode(data, (address));

        // register asset as collateral
        // any position-specific validation must be done within the position contract
        Position(position).addToken(asset);

        emit AddToken(position, msg.sender, asset);
    }

    /// @dev Remove a token address from the set of position assets
    function removeToken(address position, bytes calldata data) internal whenNotPaused {
        // asset -> address of asset to be deregistered as collateral
        address asset = abi.decode(data, (address));

        // deregister asset as collateral
        Position(position).removeToken(asset);

        emit RemoveToken(position, msg.sender, asset);
    }

    /// @notice Liquidate an unhealthy position
    /// @param position Position address
    /// @param debt DebtData object for debts to be repaid
    /// @param positionAssets AssetData object for assets to be seized
    function liquidate(address position, DebtData[] calldata debt, AssetData[] calldata positionAssets) external nonReentrant {
        // position must breach risk thresholds before liquidation
        if (riskEngine.isPositionHealthy(position)) revert PositionManager_LiquidateHealthyPosition(position);

        // verify that the liquidator seized by the liquidator is within liquidiation discount
        riskEngine.validateLiquidation(debt, positionAssets);

        // sequentially repay position debts
        // assumes the position manager is approved to pull assets from the liquidator
        for (uint256 i; i < debt.length; ++i) {
            // verify that the asset being repaid is actually the pool asset
            address poolAsset = pool.getPoolAssetFor(debt[i].poolId);

            // transfer debt asset from the liquidator to the pool
            IERC20(poolAsset).transferFrom(msg.sender, address(pool), debt[i].amt);

            // trigger pool repayment which assumes successful transfer of repaid assets
            pool.repay(debt[i].poolId, position, debt[i].amt);

            // update position to reflect repayment of debt by liquidator
            Position(position).repay(debt[i].poolId, debt[i].amt);
        }

        // transfer position assets to the liqudiator and accrue protocol liquidation fees
        for (uint256 i; i < positionAssets.length; ++i) {
            // compute fee amt
            // [ROUND] liquidation fee is rounded down, in favor of the liquidator
            uint256 fee = liquidationFee.mulDiv(positionAssets[i].amt, 1e18);

            // transfer fee amt to protocol
            Position(position).transfer(owner(), positionAssets[i].asset, fee);

            // transfer difference to the liquidator
            Position(position).transfer(msg.sender, positionAssets[i].asset, positionAssets[i].amt - fee);
        }

        // position should be within risk thresholds after liqudiation
        if (!riskEngine.isPositionHealthy(position)) revert PositionManager_HealthCheckFailed(position);

        emit Liquidation(position, msg.sender, ownerOf[position]);
    }

    /// @notice Set the position beacon used to point to the position implementation
    function setBeacon(address _positionBeacon) external onlyOwner {
        positionBeacon = _positionBeacon;
        emit BeaconSet(_positionBeacon);
    }

    /// @notice Set the protocol registry address
    function setRegistry(address _registry) external onlyOwner {
        registry = Registry(_registry);
        emit RegistrySet(_registry);
    }

    /// @notice Update the protocol liqudiation fee
    function setLiquidationFee(uint256 _liquidationFee) external onlyOwner {
        liquidationFee = _liquidationFee;
        emit LiquidationFeeSet(_liquidationFee);
    }

    /// @notice Toggle address inclusion in the known address universe
    function toggleKnownAddress(address target) external onlyOwner {
        isKnownAddress[target] = !isKnownAddress[target];
        emit ToggleKnownAddress(target, isKnownAddress[target]);
    }

    /// @notice Toggle target-function pair inclusion in the known function universe
    function toggleKnownFunc(address target, bytes4 method) external onlyOwner {
        isKnownFunc[target][method] = !isKnownFunc[target][method];
        emit ToggleKnownFunc(target, method, isKnownFunc[target][method]);
    }
}
