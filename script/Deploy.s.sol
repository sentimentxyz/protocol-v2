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

import {BaseScript} from "./BaseScript.s.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

struct DeployParams {
    address owner;
    address feeRecipient;
    uint256 minLtv;
    uint256 maxLtv;
    uint256 minDebt;
    uint256 liquidationFee;
    uint256 liquidationDiscount;
}

contract Deploy is BaseScript {
    // registry
    address public registry;
    // superpool
    address public superPoolFactory;
    // position manager
    address public positionManager;
    address public positionManagerImpl;
    // risk
    address public riskEngine;
    address public riskModule;
    // pool
    address public pool;
    address public poolImpl;
    // position
    address public positionBeacon;
    // lens
    address public superPoolLens;
    address public portfolioLens;

    DeployParams params;

    function run() public {
        getParams();

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // registry
        registry = address(new Registry());

        // risk engine
        riskEngine = address(new RiskEngine(registry, params.minLtv, params.maxLtv));
        riskModule = address(new RiskModule(registry, params.minDebt, params.liquidationDiscount));

        // pool
        poolImpl = address(new Pool());
        pool = address(new TransparentUpgradeableProxy(poolImpl, params.owner, new bytes(0)));
        Pool(pool).initialize(registry, params.feeRecipient);
        // pool = address(new Pool(registry, params.feeRecipient));

        // super pool
        superPoolFactory = address(new SuperPoolFactory(pool));

        // position manager
        positionManagerImpl = address(new PositionManager()); // deploy impl
        positionManager = address(new TransparentUpgradeableProxy(positionManagerImpl, params.owner, new bytes(0))); // setup proxy
        PositionManager(positionManager).initialize(registry, params.liquidationFee);

        // position
        positionBeacon = address(new Position(pool, positionManager));

        // lens
        superPoolLens = address(new SuperPoolLens(pool));
        portfolioLens = address(new PortfolioLens(pool, positionManager));

        // update from registry
        Pool(pool).updateFromRegistry();
        RiskEngine(riskEngine).updateFromRegistry();
        PositionManager(positionManager).updateFromRegistry();

        Pool(pool).transferOwnership(params.owner);
        Registry(registry).transferOwnership(params.owner);
        RiskEngine(riskEngine).transferOwnership(params.owner);
        PositionManager(positionManager).transferOwnership(params.owner);
        vm.stopBroadcast();

        if (block.chainid != 31337) generateLogs();
    }

    function getParams() internal {
        string memory config = getConfig();

        params.owner = vm.parseJsonAddress(config, "$.DeployParams.owner");
        params.feeRecipient = vm.parseJsonAddress(config, "$.DeployParams.feeRecipient");
        params.minLtv = vm.parseJsonUint(config, "$.DeployParams.minLtv");
        params.maxLtv = vm.parseJsonUint(config, "$.DeployParams.maxLtv");
        params.minDebt = vm.parseJsonUint(config, "$.DeployParams.minDebt");
        params.liquidationFee = vm.parseJsonUint(config, "$.DeployParams.liquidationFee");
        params.liquidationDiscount = vm.parseJsonUint(config, "$.DeployParams.liquidationDiscount");
    }

    function generateLogs() internal {
        string memory obj = "Deploy";

        vm.serializeAddress(obj, "positionManager", positionManager);
        vm.serializeAddress(obj, "positionManagerImpl", positionManagerImpl);

        vm.serializeAddress(obj, "riskEngine", riskEngine);

        vm.serializeAddress(obj, "superPoolLens", superPoolLens);
        vm.serializeAddress(obj, "portfolioLens", portfolioLens);

        vm.serializeUint(obj, "chainId", block.chainid);
        string memory json = vm.serializeUint(obj, "timestamp", vm.getBlockTimestamp());

        string memory path = string.concat(getLogPathBase(), "Deploy-", vm.toString(vm.getBlockTimestamp()), ".json");
        vm.writeJson(json, path);
    }
}
