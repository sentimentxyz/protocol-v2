// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PoolFactory} from "src/PoolFactory.sol";
import {Pool} from "src/Pool.sol";
import {RiskEngine} from "src/RiskEngine.sol";
import {PositionManager} from "src/PositionManager.sol";
import {OWNER} from "./Constants.sol";

// position impls
import {SingleAssetPosition} from "src/position/SingleAssetPosition.sol";
import {SingleDebtPosition} from "src/position/SingleDebtPosition.sol";

// healtcheck impls
import {SingleAssetRiskModule} from "src/risk/SingleAssetRiskModule.sol";
import {SingleDebtRiskModule} from "src/risk/SingleDebtRiskModule.sol";

// lens contracts
import {SuperPoolLens} from "src/lens/SuperPoolLens.sol";
import {PortfolioLens} from "src/lens/PortfolioLens.sol";

contract Deploy is Script {
    // standard contracts
    PoolFactory public poolFactory;
    SingleDebtRiskModule public singleDebtRiskModule;
    SingleAssetRiskModule public singleAssetRiskModule;

    // transparent erc1967 proxies
    RiskEngine public riskEngine;
    Pool public poolImplementation;
    PositionManager public positionManager;

    // beacon contracts
    UpgradeableBeacon public singleDebtPositionBeacon;
    UpgradeableBeacon public singleAssetPositionBeacon;

    // implementation contracts
    RiskEngine public riskEngineImpl;
    PositionManager public positionManagerImpl;
    SingleDebtPosition public singleDebtPositionImpl;
    SingleAssetPosition public singleAssetPositionImpl;

    // lens contracts
    SuperPoolLens public superPoolLens;
    PortfolioLens public portfolioLens;

    /// @notice uses values from the constants file in src/
    function run() public {
        run(OWNER);
    }

    function run(address owner) public {
        // set up positon manager and proxy
        positionManagerImpl = new PositionManager();
        TransparentUpgradeableProxy proxy1 = new TransparentUpgradeableProxy(address(positionManagerImpl), owner, "");
        positionManager = PositionManager(payable(address(proxy1)));
        positionManager.initialize();

        // set up risk engine and proxy
        riskEngineImpl = new RiskEngine();
        TransparentUpgradeableProxy proxy2 = new TransparentUpgradeableProxy(address(riskEngineImpl), owner, "");
        riskEngine = RiskEngine(payable(address(proxy2)));
        riskEngine.initialize(type(uint256).min, type(uint256).max);

        // deploy pool impl and factory
        poolImplementation = new Pool(address(positionManager));
        poolFactory = new PoolFactory(address(poolImplementation));

        // deploy health checks
        singleAssetRiskModule = new SingleAssetRiskModule(address(riskEngine));
        singleDebtRiskModule = new SingleDebtRiskModule(address(riskEngine));

        // deploy positions and setup becaons
        singleAssetPositionImpl = new SingleAssetPosition(address(positionManager));
        singleDebtPositionImpl = new SingleDebtPosition(address(positionManager));
        singleAssetPositionBeacon = new UpgradeableBeacon(address(singleAssetPositionImpl), owner);
        singleDebtPositionBeacon = new UpgradeableBeacon(address(singleDebtPositionImpl), owner);

        // set up position manager
        positionManager.setBeacon(singleDebtPositionImpl.TYPE(), address(singleDebtPositionBeacon));
        positionManager.setBeacon(singleAssetPositionImpl.TYPE(), address(singleAssetPositionBeacon));
        positionManager.setRiskEngine(address(riskEngine));
        positionManager.setPoolFactory(address(poolFactory));

        // set up risk engine
        riskEngine.setRiskModule(singleAssetPositionImpl.TYPE(), address(singleAssetRiskModule));
        riskEngine.setRiskModule(singleDebtPositionImpl.TYPE(), address(singleDebtRiskModule));

        // deploy lens contracts
        superPoolLens = new SuperPoolLens();
        portfolioLens = new PortfolioLens(address(positionManager));

        // clean up
        positionManager.transferOwnership(owner);
        riskEngine.transferOwnership(owner);
        poolFactory.transferOwnership(owner);
    }
}
