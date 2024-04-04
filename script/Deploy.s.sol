// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Pool} from "src/Pool.sol";
import {RiskEngine} from "src/RiskEngine.sol";
import {PoolFactory} from "src/PoolFactory.sol";
import {IPosition} from "src/interface/IPosition.sol";
import {PositionManager} from "src/PositionManager.sol";
import {SuperPoolLens} from "src/lens/SuperPoolLens.sol";
import {PortfolioLens} from "src/lens/PortfolioLens.sol";
import {SingleDebtPosition} from "src/position/SingleDebtPosition.sol";
import {SingleDebtRiskModule} from "src/risk/SingleDebtRiskModule.sol";
import {SingleAssetPosition} from "src/position/SingleAssetPosition.sol";
import {SingleAssetRiskModule} from "src/risk/SingleAssetRiskModule.sol";

import {BaseScript} from "./BaseScript.s.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

struct DeployParams {
    address owner;
    uint256 minLtv;
    uint256 maxLtv;
    uint256 liqFee;
    uint256 liqDiscount;
}

contract Deploy is BaseScript {
    // position manager
    address public positionManager;
    address public positionManagerImpl;

    // pool factory
    address public poolImpl;
    address public poolFactory;

    // risk engine
    address public riskEngine;
    address public riskEngineImpl;

    // single asset position
    address public singleAssetRiskModule;
    address public singleAssetPositionImpl;
    address public singleAssetPositionBeacon;

    // single debt position
    address public singleDebtRiskModule;
    address public singleDebtPositionImpl;
    address public singleDebtPositionBeacon;

    // lens
    address public superPoolLens;
    address public portfolioLens;

    DeployParams params;

    function run() public {
        getParams();

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        positionManagerImpl = address(new PositionManager());
        positionManager = address(new TransparentUpgradeableProxy(positionManagerImpl, params.owner, new bytes(0)));

        poolFactory = address(new PoolFactory(params.owner, positionManager));

        riskEngineImpl = address(new RiskEngine());
        riskEngine = address(new TransparentUpgradeableProxy(riskEngineImpl, params.owner, new bytes(0)));

        singleDebtRiskModule = address(new SingleDebtRiskModule(riskEngine));
        singleAssetRiskModule = address(new SingleAssetRiskModule(riskEngine));

        singleDebtPositionImpl = address(new SingleDebtPosition(positionManager));
        singleAssetPositionImpl = address(new SingleAssetPosition(positionManager));

        singleDebtPositionBeacon = address(new UpgradeableBeacon(singleDebtPositionImpl, params.owner));
        singleAssetPositionBeacon = address(new UpgradeableBeacon(singleAssetPositionImpl, params.owner));

        superPoolLens = address(new SuperPoolLens());
        portfolioLens = address(new PortfolioLens(positionManager));

        RiskEngine(riskEngine).initialize(params.minLtv, params.maxLtv, params.liqDiscount);
        RiskEngine(riskEngine).setRiskModule(IPosition(singleDebtPositionImpl).TYPE(), singleDebtRiskModule);
        RiskEngine(riskEngine).setRiskModule(IPosition(singleAssetPositionImpl).TYPE(), singleAssetRiskModule);

        PositionManager(positionManager).initialize(poolFactory, riskEngine, params.liqFee);
        PositionManager(positionManager).setBeacon(IPosition(singleDebtPositionImpl).TYPE(), singleDebtPositionBeacon);
        PositionManager(positionManager).setBeacon(IPosition(singleAssetPositionImpl).TYPE(), singleAssetPositionBeacon);

        RiskEngine(riskEngine).transferOwnership(params.owner);
        PositionManager(positionManager).transferOwnership(params.owner);
        vm.stopBroadcast();

        if (block.chainid != 31337) generateLogs();
    }

    function getParams() internal {
        string memory config = getConfig();

        params.minLtv = vm.parseJsonUint(config, "$.Deploy.minLtv");
        params.maxLtv = vm.parseJsonUint(config, "$.Deploy.maxLtv");
        params.liqFee = vm.parseJsonUint(config, "$.Deploy.liqFee");
        params.owner = vm.parseJsonAddress(config, "$.Deploy.owner");
        params.liqDiscount = vm.parseJsonUint(config, "$.Deploy.liqDiscount");
    }

    function generateLogs() internal {
        string memory obj = "Deploy";

        vm.serializeAddress(obj, "positionManager", positionManager);
        vm.serializeAddress(obj, "positionManagerImpl", positionManagerImpl);

        vm.serializeAddress(obj, "poolImpl", poolImpl);
        vm.serializeAddress(obj, "poolFactory", poolFactory);

        vm.serializeAddress(obj, "riskEngine", riskEngine);
        vm.serializeAddress(obj, "riskEngineImpl", riskEngineImpl);

        vm.serializeAddress(obj, "singleAssetRiskModule", singleAssetRiskModule);
        vm.serializeAddress(obj, "singleAssetPositionImpl", singleAssetPositionImpl);
        vm.serializeAddress(obj, "singleAssetPositionBeacon", singleAssetPositionBeacon);

        vm.serializeAddress(obj, "singleDebtRiskModule", singleDebtRiskModule);
        vm.serializeAddress(obj, "singleDebtPositionImpl", singleDebtPositionImpl);
        vm.serializeAddress(obj, "singleDebtPositionBeacon", singleDebtPositionBeacon);

        vm.serializeAddress(obj, "superPoolLens", superPoolLens);
        vm.serializeAddress(obj, "portfolioLens", portfolioLens);

        vm.serializeUint(obj, "chainId", block.chainid);
        string memory json = vm.serializeUint(obj, "timestamp", vm.getBlockTimestamp());

        string memory path = string.concat(getLogPathBase(), "Deploy-", vm.toString(vm.getBlockTimestamp()), ".json");
        vm.writeJson(json, path);
    }
}
