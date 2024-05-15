// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Pool} from "src/Pool.sol";
import {Registry} from "src/Registry.sol";
import {Position} from "src/Position.sol";
import {RiskEngine} from "src/RiskEngine.sol";
import {RiskModule} from "src/RiskModule.sol";
import {PositionManager} from "src/PositionManager.sol";
import {SuperPoolLens} from "src/lens/SuperPoolLens.sol";
import {PortfolioLens} from "src/lens/PortfolioLens.sol";
import {SuperPoolFactory} from "src/SuperPoolFactory.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {FixedRateModel} from "../src/irm/FixedRateModel.sol";
import {LinearRateModel} from "../src/irm/LinearRateModel.sol";

import {MockERC20} from "./mocks/MockERC20.sol";

import {Test} from "forge-std/Test.sol";

contract BaseTest is Test {
    address public protocolOwner = makeAddr("protocolOwner");

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
    address public owner = makeAddr("owner");

    MockERC20 public asset;
    uint256 public fixedRatePool;
    uint256 public linearRatePool;

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
            minDebt: 0,
            liquidationFee: 0,
            liquidationDiscount: 200000000000000000
        });

        // registry
        registry = new Registry();

        // super pool
        superPoolFactory = new SuperPoolFactory();

        // risk engine
        riskEngine = new RiskEngine(address(registry), params.minLtv, params.maxLtv);
        riskModule = new RiskModule(address(registry), params.minDebt, params.liquidationDiscount);

        // pool
        pool = new Pool(address(registry), params.feeRecipient);

        // position manager
        positionManagerImpl = address(new PositionManager()); // deploy impl
        positionManager =
            PositionManager(address(new TransparentUpgradeableProxy(positionManagerImpl, params.owner, new bytes(0)))); // setup proxy
        PositionManager(positionManager).initialize(address(registry), params.liquidationFee);

        // position
        address positionImpl = address(new Position(address(pool), address(positionManager)));
        positionBeacon = address(new UpgradeableBeacon(positionImpl, params.owner));

        // lens
        superPoolLens = new SuperPoolLens(address(pool));
        portfolioLens = new PortfolioLens(address(pool), address(positionManager));

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

        asset = new MockERC20("Asset", "ASSET", 18);

        address rateModel = address(new LinearRateModel(1e18, 2e18));
        linearRatePool = pool.initializePool(protocolOwner, address(asset), rateModel, 0, 0);

        rateModel = address(new FixedRateModel(1e18));
        fixedRatePool = pool.initializePool(protocolOwner, address(asset), rateModel, 0, 0);
    }
}

contract RegistryTest is BaseTest {
    function testInitializesRegistryCorrectly() public view {
        assertEq(address(pool), registry.addressFor(SENTIMENT_POOL_KEY));
        assertEq(address(riskEngine), registry.addressFor(SENTIMENT_RISK_ENGINE_KEY));
        assertEq(address(positionManager), registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));
        assertEq(address(positionBeacon), registry.addressFor(SENTIMENT_POSITION_BEACON_KEY));
        assertEq(address(riskModule), registry.addressFor(SENTIMENT_RISK_MODULE_KEY));

        assertEq(pool.positionManager(), address(positionManager));

        assertEq(address(positionManager.riskEngine()), address(riskEngine));
        assertEq(address(positionManager.pool()), address(pool));
        assertEq(address(positionManager.positionBeacon()), address(positionBeacon));
    }
}
