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

import {Script} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

struct DeployParams {
    address owner;
    uint256 minLtv;
    uint256 maxLtv;
    uint256 liqFee;
    uint256 liqDiscount;
    uint256 closeFactor;
}

contract Deploy is Script {
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

    function run() public {
        DeployParams memory params = getDeployParams();
        deploy(params);
    }

    function deploy(DeployParams memory params) public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        positionManagerImpl = address(new PositionManager());
        positionManager = address(new TransparentUpgradeableProxy(positionManagerImpl, params.owner, new bytes(0)));

        poolImpl = address(new Pool(positionManager));
        poolFactory = address(new PoolFactory(params.owner, poolImpl));

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

        RiskEngine(riskEngine).initialize(params.minLtv, params.maxLtv, params.closeFactor, params.liqDiscount);
        RiskEngine(riskEngine).setRiskModule(IPosition(singleDebtPositionImpl).TYPE(), singleDebtRiskModule);
        RiskEngine(riskEngine).setRiskModule(IPosition(singleAssetPositionImpl).TYPE(), singleAssetRiskModule);

        PositionManager(positionManager).initialize(poolFactory, riskEngine, params.liqFee);
        PositionManager(positionManager).setBeacon(IPosition(singleDebtPositionImpl).TYPE(), singleDebtPositionBeacon);
        PositionManager(positionManager).setBeacon(IPosition(singleAssetPositionImpl).TYPE(), singleAssetPositionBeacon);

        RiskEngine(riskEngine).transferOwnership(params.owner);
        PositionManager(positionManager).transferOwnership(params.owner);
        vm.stopBroadcast();
    }

    function getDeployParams() internal view returns (DeployParams memory params) {
        string memory path =
            string.concat(vm.projectRoot(), "/script/config/", vm.toString(block.chainid), "/deploy.json");
        string memory config = vm.readFile(path);

        params.minLtv = vm.parseJsonUint(config, "$.minLtv");
        params.maxLtv = vm.parseJsonUint(config, "$.maxLtv");
        params.liqFee = vm.parseJsonUint(config, "$.liqFee");
        params.owner = vm.parseJsonAddress(config, "$.owner");
        params.liqDiscount = vm.parseJsonUint(config, "$.liqDiscount");
        params.closeFactor = vm.parseJsonUint(config, "$.closeFactor");
    }
}
