// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "./BaseScript.s.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Pool } from "src/Pool.sol";
import { Position } from "src/Position.sol";
import { PositionManager } from "src/PositionManager.sol";
import { Registry } from "src/Registry.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { RiskModule } from "src/RiskModule.sol";
import { SuperPoolFactory } from "src/SuperPoolFactory.sol";
import { PortfolioLens } from "src/lens/PortfolioLens.sol";
import { SuperPoolLens } from "src/lens/SuperPoolLens.sol";

contract Deploy is BaseScript {
    // registry
    Registry public registry;
    // superpool factory
    SuperPoolFactory public superPoolFactory;
    // position manager
    address positionManagerImpl;
    PositionManager public positionManager;
    // risk
    RiskEngine public riskEngine;
    RiskModule public riskModule;
    // pool
    address poolImpl;
    Pool public pool;
    // position
    address public positionBeacon;
    // lens
    SuperPoolLens public superPoolLens;
    PortfolioLens public portfolioLens;

    struct DeployParams {
        address owner;
        address proxyAdmin;
        address feeRecipient;
        uint256 minLtv;
        uint256 maxLtv;
        uint256 minDebt;
        uint256 liquidationFee;
        uint256 liquidationDiscount;
    }

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

    function run() public {
        DeployParams memory params = fetchParams();
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        runWithParams(params);
        vm.stopBroadcast();
    }

    function runWithParams(DeployParams memory params) public {
        // registry
        registry = new Registry();
        // risk
        riskEngine = new RiskEngine(address(registry), params.minLtv, params.maxLtv);
        riskEngine.transferOwnership(params.owner);
        riskModule = new RiskModule(address(registry), params.minDebt, params.liquidationDiscount);
        // pool
        poolImpl = address(new Pool());
        bytes memory poolInitData =
            abi.encodeWithSelector(Pool.initialize.selector, params.owner, address(registry), params.feeRecipient);
        pool = Pool(address(new TransparentUpgradeableProxy(poolImpl, params.proxyAdmin, poolInitData)));
        // super pool factory
        superPoolFactory = new SuperPoolFactory(address(pool));
        // position manager
        positionManagerImpl = address(new PositionManager());
        bytes memory posmgrInitData = abi.encodeWithSelector(
            PositionManager.initialize.selector, params.owner, address(registry), params.liquidationFee
        );
        positionManager = PositionManager(
            address(new TransparentUpgradeableProxy(positionManagerImpl, params.proxyAdmin, posmgrInitData))
        );
        // position
        address positionImpl = address(new Position(address(pool), address(positionManager)));
        positionBeacon = address(new UpgradeableBeacon(positionImpl));
        // lens
        superPoolLens = new SuperPoolLens(address(pool), address(riskEngine));
        portfolioLens = new PortfolioLens(address(pool), address(riskEngine), address(positionManager));
        // register modules
        registry.setAddress(SENTIMENT_POSITION_MANAGER_KEY, address(positionManager));
        registry.setAddress(SENTIMENT_POOL_KEY, address(pool));
        registry.setAddress(SENTIMENT_RISK_ENGINE_KEY, address(riskEngine));
        registry.setAddress(SENTIMENT_POSITION_BEACON_KEY, address(positionBeacon));
        registry.setAddress(SENTIMENT_RISK_MODULE_KEY, address(riskModule));
        registry.transferOwnership(params.owner);
        // update module addresses
        pool.updateFromRegistry();
        positionManager.updateFromRegistry();
        riskEngine.updateFromRegistry();
        riskModule.updateFromRegistry();

        if (block.chainid != 31_337) generateLogs();
    }

    function fetchParams() internal view returns (DeployParams memory params) {
        string memory config = getConfig();

        params.owner = vm.parseJsonAddress(config, "$.DeployParams.owner");
        params.proxyAdmin = vm.parseJsonAddress(config, "$.DeployParams.proxyAdmin");
        params.feeRecipient = vm.parseJsonAddress(config, "$.DeployParams.feeRecipient");
        params.minLtv = vm.parseJsonUint(config, "$.DeployParams.minLtv");
        params.maxLtv = vm.parseJsonUint(config, "$.DeployParams.maxLtv");
        params.minDebt = vm.parseJsonUint(config, "$.DeployParams.minDebt");
        params.liquidationFee = vm.parseJsonUint(config, "$.DeployParams.liquidationFee");
        params.liquidationDiscount = vm.parseJsonUint(config, "$.DeployParams.liquidationDiscount");
    }

    function generateLogs() internal {
        string memory obj = "Deploy";

        // Registry
        vm.serializeAddress(obj, "registry", address(registry));
        // SuperPool Factory
        vm.serializeAddress(obj, "superPoolFactory", address(superPoolFactory));
        // Position Manager
        vm.serializeAddress(obj, "positionManagerImpl", address(positionManagerImpl));
        vm.serializeAddress(obj, "positionManager", address(positionManager));
        // Risk
        vm.serializeAddress(obj, "riskEngine", address(riskEngine));
        vm.serializeAddress(obj, "riskModule", address(riskModule));
        // Pool
        vm.serializeAddress(obj, "poolImpl", address(poolImpl));
        vm.serializeAddress(obj, "pool", address(pool));
        // Position
        vm.serializeAddress(obj, "positionBeacon", address(positionBeacon));
        // Lens
        vm.serializeAddress(obj, "superPoolLens", address(superPoolLens));
        vm.serializeAddress(obj, "portfolioLens", address(portfolioLens));

        vm.serializeUint(obj, "chainId", block.chainid);
        string memory json = vm.serializeUint(obj, "timestamp", vm.getBlockTimestamp());

        string memory path = string.concat(getLogPathBase(), "Deploy-", vm.toString(vm.getBlockTimestamp()), ".json");
        vm.writeJson(json, path);
    }
}
