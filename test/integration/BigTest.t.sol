// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Pool} from "src/Pool.sol";
import {Registry} from "src/Registry.sol";
import {Position} from "src/Position.sol";
import {RiskEngine} from "src/RiskEngine.sol";
import {RiskModule} from "src/RiskModule.sol";
import {SuperPoolLens} from "src/lens/SuperPoolLens.sol";
import {PortfolioLens} from "src/lens/PortfolioLens.sol";
import {SuperPoolFactory} from "src/SuperPoolFactory.sol";
import {SuperPool} from "src/SuperPool.sol";
import {Action, Operation, PositionManager} from "src/PositionManager.sol";
import {FixedPriceOracle} from "../../src/oracle/FixedPriceOracle.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {FixedRateModel} from "../../src/irm/FixedRateModel.sol";
import {LinearRateModel} from "../../src/irm/LinearRateModel.sol";

import {MockERC20} from "../mocks/MockERC20.sol";

import {Test} from "forge-std/Test.sol";

contract BigTest is Test {
    address public protocolOwner = makeAddr("protocolOwner");

    address poolImpl;
    Registry public registry;
    SuperPoolFactory public superPoolFactory;
    PositionManager public positionManager;
    address positionManagerImpl; // Shouldn't be called directly
    RiskEngine public riskEngine;
    RiskModule public riskModule;
    PortfolioLens public portfolioLens;
    SuperPoolLens public superPoolLens;
    address public positionBeacon;
    Pool public pool;

    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");

    address public lender = makeAddr("lender");
    address public poolOwner = makeAddr("poolOwner");

    MockERC20 public asset1;
    MockERC20 public asset2;

    uint256 public fixedRatePool;
    uint256 public linearRatePool;
    uint256 public fixedRatePool2;
    uint256 public linearRatePool2;
    uint256 public alternateAssetPool;

    // keccak(SENTIMENT_POSITION_MANAGER_KEY)
    bytes32 public constant SENTIMENT_POSITION_MANAGER_KEY =
        0xd4927490fbcbcafca716cca8e8c8b7d19cda785679d224b14f15ce2a9a93e148;
    // keccak(SENTIMENT_POOL_KEY)
    bytes32 public constant SENTIMENT_POOL_KEY = 0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728;
    // keccak(SENTIMENT_RISK_ENGINE_KEY)
    bytes32 public constant SENTIMENT_RISK_ENGINE_KEY =
        0x5b6696788621a5d6b5e3b02a69896b9dd824ebf1631584f038a393c29b6d7555;
    // keccak(SENIMENT_POSITION_BEACON_KEY)
    bytes32 public constant SENTIMENT_POSITION_BEACON_KEY =
        0xc77ea3242ed8f193508dbbe062eaeef25819b43b511cbe2fc5bd5de7e23b9990;
    // keccak(SENTIMENT_RISK_MODULE_KEY)
    bytes32 public constant SENTIMENT_RISK_MODULE_KEY =
        0x881469d14b8443f6c918bdd0a641e9d7cae2592dc28a4f922a2c4d7ca3d19c77;

    FixedPriceOracle asset1Oracle = new FixedPriceOracle(10e18);
    FixedPriceOracle asset2Oracle = new FixedPriceOracle(1e18);

    struct DeployParams {
        address owner;
        address feeRecipient;
        uint256 minLtv;
        uint256 maxLtv;
        uint256 minDebt;
        uint256 liquidationFee;
        uint256 liquidationDiscount;
    }

    function setUp() public virtual {
        DeployParams memory params = DeployParams({
            owner: protocolOwner,
            feeRecipient: address(this),
            minLtv: 0,
            maxLtv: 115792089237316195423570985008687907853269984665640564039457584007913129639935,
            minDebt: 0.03 ether,
            liquidationFee: 0,
            liquidationDiscount: 200000000000000000
        });

        // registry
        registry = new Registry();

        // risk engine
        riskEngine = new RiskEngine(address(registry), params.minLtv, params.maxLtv);
        riskModule = new RiskModule(address(registry), params.minDebt, params.liquidationDiscount);

        // pool
        poolImpl = address(new Pool());
        pool = Pool(address(new TransparentUpgradeableProxy(poolImpl, params.owner, new bytes(0))));
        pool.initialize(address(registry), params.feeRecipient);
        // pool = new Pool(address(registry), params.feeRecipient);

        // super pool
        superPoolFactory = new SuperPoolFactory(address(pool));

        // position manager
        positionManagerImpl = address(new PositionManager()); // deploy impl
        positionManager =
            PositionManager(address(new TransparentUpgradeableProxy(positionManagerImpl, params.owner, new bytes(0)))); // setup proxy
        PositionManager(positionManager).initialize(address(registry), params.liquidationFee);

        // position
        address positionImpl = address(new Position(address(pool), address(positionManager)));
        positionBeacon = address(new UpgradeableBeacon(positionImpl, params.owner));

        // lens
        superPoolLens = new SuperPoolLens(address(pool), address(riskEngine));
        portfolioLens = new PortfolioLens(address(pool), address(riskEngine), address(positionManager));

        PositionManager(positionManager).transferOwnership(params.owner);

        // register
        registry.setAddress(SENTIMENT_POSITION_MANAGER_KEY, address(positionManager));
        registry.setAddress(SENTIMENT_POOL_KEY, address(pool));
        registry.setAddress(SENTIMENT_RISK_ENGINE_KEY, address(riskEngine));
        registry.setAddress(SENTIMENT_POSITION_BEACON_KEY, address(positionBeacon));
        registry.setAddress(SENTIMENT_RISK_MODULE_KEY, address(riskModule));

        pool.updateFromRegistry();
        positionManager.updateFromRegistry();
        riskEngine.updateFromRegistry();
        riskModule.updateFromRegistry();

        asset1 = new MockERC20("Asset1", "ASSET1", 18);
        asset2 = new MockERC20("Asset2", "ASSET2", 18);

        pool.transferOwnership(params.owner);
        registry.transferOwnership(params.owner);
        riskEngine.transferOwnership(params.owner);

        address fixedRateModel = address(new FixedRateModel(1e18));
        address linearRateModel = address(new LinearRateModel(1e18, 2e18));
        address fixedRateModel2 = address(new FixedRateModel(2e18));

        vm.startPrank(protocolOwner);
        riskEngine.setOracle(address(asset1), address(asset1Oracle));
        riskEngine.setOracle(address(asset2), address(asset2Oracle));
        vm.stopPrank();

        vm.startPrank(poolOwner);
        fixedRatePool =
            pool.initializePool(poolOwner, address(asset1), fixedRateModel, 0.1e18, 0.01e18, type(uint128).max);
        linearRatePool =
            pool.initializePool(poolOwner, address(asset1), linearRateModel, 0.1e18, 0.01e18, type(uint128).max);
        fixedRatePool2 =
            pool.initializePool(poolOwner, address(asset1), fixedRateModel2, 0.1e18, 0.01e18, type(uint128).max);
        vm.stopPrank();

        vm.startPrank(poolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset1));
        riskEngine.requestLtvUpdate(linearRatePool, address(asset2), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset2));

        riskEngine.requestLtvUpdate(fixedRatePool, address(asset1), 0.75e18);
        riskEngine.acceptLtvUpdate(fixedRatePool, address(asset1));
        riskEngine.requestLtvUpdate(fixedRatePool, address(asset2), 0.75e18);
        riskEngine.acceptLtvUpdate(fixedRatePool, address(asset2));

        riskEngine.requestLtvUpdate(fixedRatePool2, address(asset1), 0.75e18);
        riskEngine.acceptLtvUpdate(fixedRatePool2, address(asset1));
        riskEngine.requestLtvUpdate(fixedRatePool2, address(asset2), 0.75e18);
        riskEngine.acceptLtvUpdate(fixedRatePool2, address(asset2));
        vm.stopPrank();
    }

    function newPosition(address owner, bytes32 salt) internal view returns (address, Action memory) {
        bytes memory data = abi.encode(owner, salt);
        (address position,) = portfolioLens.predictAddress(owner, salt);
        Action memory action = Action({op: Operation.NewPosition, data: data});
        return (position, action);
    }

    function deposit(address asset, uint256 amt) internal pure returns (Action memory) {
        bytes memory data = abi.encode(asset, amt);
        Action memory action = Action({op: Operation.Deposit, data: data});
        return action;
    }

    function addToken(address asset) internal pure returns (Action memory) {
        bytes memory data = abi.encode(asset);
        Action memory action = Action({op: Operation.AddToken, data: data});
        return action;
    }

    function removeToken(address asset) internal pure returns (Action memory) {
        bytes memory data = abi.encode(asset);
        Action memory action = Action({op: Operation.RemoveToken, data: data});
        return action;
    }

    function borrow(uint256 poolId, uint256 amt) internal pure returns (Action memory) {
        bytes memory data = abi.encode(poolId, amt);
        Action memory action = Action({op: Operation.Borrow, data: data});
        return action;
    }

    function testMultiPoolProfitScenario() public {
        // 1. Set up 3 pools with a 100 ether cap each
        // 2. Make a SuperPool with the 3 pools
        // 3. User fills up the pool
        // 4. User2 borrows from 2 of the pools
        // 5. Advance time
        // 6. User2 repays the borrowed amount
        // 7. User should have profit from the borrowed amount
        // 8. feeTo should make money
        address feeTo = makeAddr("feeTo");
        SuperPool superPool = SuperPool(
            superPoolFactory.deploy(poolOwner, address(asset1), feeTo, 0.01 ether, 1_000_000 ether, "test", "test")
        );

        // 2. Make a SuperPool with the 3 pools
        vm.startPrank(poolOwner);
        superPool.setPoolCap(fixedRatePool, 100 ether);
        superPool.setPoolCap(fixedRatePool2, 100 ether);
        superPool.setPoolCap(linearRatePool, 100 ether);
        vm.stopPrank();

        // 3. User fills up the pool
        vm.startPrank(user);
        asset1.mint(user, 300 ether);
        asset1.approve(address(superPool), 300 ether);
        superPool.deposit(300 ether, user);

        uint256 initialAmountCanBeWithdrawn = superPool.maxWithdraw(user);
        vm.stopPrank();

        // 4. User2 borrows from 2 of the pools
        vm.startPrank(user2);
        asset2.mint(user2, 300 ether);
        asset2.approve(address(positionManager), 300 ether);

        // Make a new position
        (address position, Action memory _newPosition) = newPosition(user2, "test");
        positionManager.process(position, _newPosition);

        Action memory addNewCollateral = addToken(address(asset2));
        Action memory depositCollateral = deposit(address(asset2), 300 ether);
        Action memory borrowAct = borrow(fixedRatePool, 15 ether);

        Action[] memory actions = new Action[](3);
        actions[0] = addNewCollateral;
        actions[1] = depositCollateral;
        actions[2] = borrowAct;

        positionManager.processBatch(position, actions);
        vm.stopPrank();

        // 5. Advance time
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + (365 days / 12));

        // 6. User2 repays the borrowed amount
        vm.startPrank(user2);
        pool.accrue(fixedRatePool);
        uint256 debt = pool.getBorrowsOf(fixedRatePool, position);

        asset1.mint(position, debt);

        Action memory _repay = Action({op: Operation.Repay, data: abi.encode(fixedRatePool, debt)});
        positionManager.process(position, _repay);
        vm.stopPrank();

        // 7. User should have profit from the borrowed amount
        vm.startPrank(user);
        superPool.accrueInterestAndFees();
        assertTrue(superPool.maxWithdraw(user) > initialAmountCanBeWithdrawn);
        vm.stopPrank();
    }
}
