// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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
    mapping(address caller => mapping(address position => bool isAuthz)) public auth;

    // defines the universe of approved contracts and methods that a position can interact with
    // mapping key -> first 20 bytes store the target address, next 4 bytes store the method selector
    mapping(address target => bool isAllowed) public contractUniverse;
    mapping(address target => mapping(bytes4 method => bool isAllowed)) public funcUniverse;

    error InvalidPool();
    error Unauthorized();
    error InvalidOperation();
    error HealthCheckFailed();
    error InvalidPositionType();

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        OwnableUpgradeable.__Ownable_init(msg.sender);
        PausableUpgradeable.__Pausable_init();
    }

    /*//////////////////////////////////////////////////////////////
                          External Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice allow other addresses to call process() on behalf of the position owner
    function setAuth(address user, address position, bool isAuthorized) external {
        // only account owners are allowed to modify authorizations
        // disables transitive auth operations
        if (msg.sender != ownerOf[position]) revert Unauthorized();

        // update authz status in storage
        auth[user][position] = isAuthorized;
    }

    /*//////////////////////////////////////////////////////////////
                         Position Interaction
    //////////////////////////////////////////////////////////////*/

    // defines various operation types that can be applied to a position
    // every operation except NewPosition requires that the caller must be an authz caller or owner
    enum Operation {
        //
        // New Position: create2 a new position with a given type
        // new positions are deployed as beacon proxies
        // anyone can create a new position
        NewPosition,
        //
        // Exec: execute arbitrary calldata on a position
        // the target contract and function must be recognized via funcUniverse
        // only owners + authz callers can exec on a position
        Exec,
        //
        // Deposit: deposit collateral assets to a given position
        // while assets can directly be transferred to the position this does
        // only owners + authz callers can deposit to a position
        Deposit,
        //
        // Transfer: transfer assets from the position to a external address
        // only owners + authz callers can deposit to a position
        Transfer,
        //
        // Approve: allow a spender to transfer assets from a position
        // the spender address must be recognized via contractUniverse
        // behaves as a wrapper over ERC20 approve for the position
        // only owners + authz callers can deposit to a position
        Approve,
        //
        // Repay: decrease position debt
        // transfers debt assets from the position back to the given pool
        // and decreases position debt
        Repay,
        //
        // Borrow: increase position debt
        // transfers debt assets from the given pool to the position
        // and increases position debt
        Borrow,
        //
        // AddAsset: upsert collateral asset to position storage
        // signals position to register new collateral with sanity checks
        // each position type should handle this call differently to account for their structure
        AddAsset,
        //
        // RemoveAsset: remove collateral asset from position storage
        // signals position to deregister a given collateral with sanity checks
        // each position type should handle this call differently to account for their structure
        RemoveAsset
    }

    // loosely defined data struct to create a common data container for all operation types
    // target and data are interpreted in different ways based on the operation type
    struct Action {
        // operation type
        Operation op;
        // target address, interpreted differently across operations types
        address target;
        // dynamic bytes data, interepreted differently across operation types
        bytes data;
    }

    /// @notice procces a batch of actions on a given position
    /// @dev only one position can be operated on in one txn, including creation
    /// @param position the position to process the actions on
    /// @param actions the list of actions to process
    function process(address position, Action[] calldata actions) external nonReentrant {
        // TODO comments
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
                if (!funcUniverse[actions[i].target][bytes4(actions[i].data[:4])]) revert InvalidOperation();
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
            } else if (actions[i].op == Operation.Approve) {
                // target -> spender
                // data -> asset and amount to be approved
                if (!contractUniverse[actions[i].target]) revert InvalidOperation();
                (address asset, uint256 amt) = abi.decode(actions[i].data, (address, uint256));
                IPosition(position).approve(asset, actions[i].target, amt);
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

    /*//////////////////////////////////////////////////////////////
                             Liquidation
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

    function liquidate(address position, DebtData[] calldata debt, AssetData[] calldata collat) external nonReentrant {
        // position must breach risk thresholds before liquidation
        if (riskEngine.isPositionHealthy(position)) revert InvalidOperation();

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
        if (!riskEngine.isPositionHealthy(position)) revert InvalidOperation();

        // TODO emit liquidation event and/or reset position
    }

    /*//////////////////////////////////////////////////////////////
                          Internal Functions
    //////////////////////////////////////////////////////////////*/

    /// @dev deterministically deploy a new beacon proxy representin a position
    function newPosition(address owner, uint256 positionType, bytes32 salt) internal returns (address) {
        // revert if given position type doesn't have a register beacon
        if (beaconFor[positionType] == address(0)) revert InvalidPositionType();

        // create2 a new position as a beacon proxy
        address position = address(new BeaconProxy{salt: salt}(beaconFor[positionType], ""));

        // update position owner
        ownerOf[position] = owner;

        // owner is authzd by default
        auth[owner][position] = true;

        // return new position address to be verified against process() calldata params
        return position;
    }

    /// @dev to repay the entire debt set _amt to uint.max
    function repay(address position, address pool, uint256 _amt) internal {
        // if the passed amt is type(uint).max assume repayment of the entire debt
        uint256 amt = (_amt == type(uint256).max) ? Pool(pool).getBorrowsOf(position) : _amt;

        // transfer assets to be repaid from the position to the given pool
        // signals repayment to the position without making any changes in the pool
        // since every position is structured differently
        // we assume that any checks needed to validate repayment are implemented in the position
        IPosition(position).repay(Pool(pool).asset(), amt);

        // trigger pool repayment which assumes successful transfer of repaid assets
        Pool(pool).repay(position, amt);
    }

    function borrow(address position, address pool, uint256 amt) internal {
        // revert if the given pool was not deployed by the protocol pool factory
        if (poolFactory.managerFor(pool) == address(0)) revert InvalidPool();

        // signals a borrow operation without any actual transfer of borrowed assets
        // since every position type is structured differently
        // we assume that the position implements any checks needed to validate the borrow
        IPosition(position).borrow(pool, amt);

        // transfer borrowed assets from given pool to position
        // trigger pool borrow and increase debt owed by the position
        Pool(pool).borrow(position, amt);
    }

    /*//////////////////////////////////////////////////////////////
                              Only Owner
    //////////////////////////////////////////////////////////////*/

    /// @notice update the beacon for a given position type
    /// @dev only callable by the position manager owner
    function setBeacon(uint256 positionType, address beacon) external onlyOwner {
        beaconFor[positionType] = beacon;
    }

    /// @notice update the risk engine address
    /// @dev only callable by the position manager owner
    function setRiskEngine(address _riskEngine) external onlyOwner {
        riskEngine = RiskEngine(_riskEngine);
    }

    /// @notice update the pool factory address
    /// @dev only callable by the position manager owner
    function setPoolFactory(address _poolFactory) external onlyOwner {
        poolFactory = PoolFactory(_poolFactory);
    }

    /// @notice update the protocol liqudiation fee
    /// @dev only callable by the position manager owner
    function setLiquidationFee(uint256 _liquidationFee) external onlyOwner {
        liquidationFee = _liquidationFee;
    }
}
