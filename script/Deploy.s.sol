// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Pool} from "src/Pool.sol";
import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
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
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

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

    // config variables
    address owner;
    uint256 liquidationFee;
    uint256 minLtv;
    uint256 maxLtv;

    function run() public {
        owner = vm.envAddress("OWNER");
        minLtv = vm.envUint("MIN_LTV");
        maxLtv = vm.envUint("MAX_LTV");

        positionManagerImpl = address(new PositionManager());
        positionManager = address(new TransparentUpgradeableProxy(positionManagerImpl, owner, new bytes(0)));

        poolImpl = address(new Pool(positionManager));
        poolFactory = address(new PoolFactory(owner, poolImpl));

        riskEngineImpl = address(new RiskEngine());
        riskEngine = address(new TransparentUpgradeableProxy(riskEngineImpl, owner, new bytes(0)));

        singleDebtRiskModule = address(new SingleDebtRiskModule(riskEngine));
        singleAssetRiskModule = address(new SingleAssetRiskModule(riskEngine));

        singleDebtPositionImpl = address(new SingleDebtPosition(positionManager));
        singleAssetPositionImpl = address(new SingleAssetPosition(positionManager));

        singleDebtPositionBeacon = address(new UpgradeableBeacon(singleDebtPositionImpl, owner));
        singleAssetPositionBeacon = address(new UpgradeableBeacon(singleAssetPositionImpl, owner));

        superPoolLens = address(new SuperPoolLens());
        portfolioLens = address(new PortfolioLens(positionManager));

        RiskEngine(riskEngine).initialize(minLtv, maxLtv);
        RiskEngine(riskEngine).setRiskModule(IPosition(singleDebtPositionImpl).TYPE(), singleDebtRiskModule);
        RiskEngine(riskEngine).setRiskModule(IPosition(singleAssetPositionImpl).TYPE(), singleAssetRiskModule);

        PositionManager(positionManager).initialize(poolFactory, riskEngine, liquidationFee);
        PositionManager(positionManager).setBeacon(IPosition(singleDebtPositionImpl).TYPE(), singleDebtPositionBeacon);
        PositionManager(positionManager).setBeacon(IPosition(singleAssetPositionImpl).TYPE(), singleAssetPositionBeacon);

        RiskEngine(riskEngine).transferOwnership(owner);
        PositionManager(positionManager).transferOwnership(owner);
    }
}
