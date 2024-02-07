// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PoolFactory} from "src/PoolFactory.sol";
import {Pool} from "src/Pool.sol";
import {RiskEngine} from "src/RiskEngine.sol";
import {PositionManager} from "src/PositionManager.sol";
// import {OWNER} from "src/Constants.sol";

// position impls
import {SingleCollatPosition} from "src/positions/SingleCollatPosition.sol";
import {SingleDebtPosition} from "src/positions/SingleDebtPosition.sol";

// healtcheck impls
import {SingleCollatHealthCheck} from "src/healthcheck/SingleCollatHealthCheck.sol";
import {SingleDebtHealthCheck} from "src/healthcheck/SingleDebtHealthCheck.sol";

contract Deploy is Script {
    SingleCollatPosition public singleCollatPositionImpl;
    SingleDebtPosition public singleDebtPositionImpl;
    UpgradeableBeacon public singleCollatPositionBeacon;
    UpgradeableBeacon public singleDebtPositionBeacon;
    SingleCollatHealthCheck public singleCollatHealthCheck;
    SingleDebtHealthCheck public singleDebtHealthCheck;
    PoolFactory public poolFactory;
    PositionManager public positionManager;
    RiskEngine public riskEngine;
    Pool public poolImplementation;

    PositionManager public positionManagerImpl;
    RiskEngine public riskEngineImpl;

    // /// @notice uses values from the constants file in src/
    // function run() public {
    //     run(OWNER);
    // }

    function run(address owner) public {
        positionManagerImpl = new PositionManager();
        TransparentUpgradeableProxy proxy1 = new TransparentUpgradeableProxy(address(positionManagerImpl), owner, "");
        positionManager = PositionManager(payable(address(proxy1)));
        positionManager.initialize();

        riskEngineImpl = new RiskEngine();
        TransparentUpgradeableProxy proxy2 = new TransparentUpgradeableProxy(address(riskEngineImpl), owner, "");
        riskEngine = RiskEngine(payable(address(proxy2)));
        riskEngine.initialize();

        poolImplementation = new Pool(address(positionManager));
        poolFactory = new PoolFactory(address(poolImplementation));

        singleCollatHealthCheck = new SingleCollatHealthCheck(address(riskEngine));
        singleDebtHealthCheck = new SingleDebtHealthCheck(address(riskEngine));

        // deploy impls and beacons
        singleCollatPositionImpl = new SingleCollatPosition();
        singleDebtPositionImpl = new SingleDebtPosition();
        singleCollatPositionBeacon = new UpgradeableBeacon(address(singleCollatPositionImpl), owner);
        singleDebtPositionBeacon = new UpgradeableBeacon(address(singleDebtPositionImpl), owner);

        // set up position manager
        positionManager.setBeacon(singleDebtPositionImpl.TYPE(), address(singleDebtPositionBeacon));
        positionManager.setBeacon(singleCollatPositionImpl.TYPE(), address(singleCollatPositionBeacon));

        positionManager.setRiskEngine(address(riskEngine));
        positionManager.setPoolFactory(address(poolFactory));

        // set up risk engine
        riskEngine.setHealthCheck(singleCollatHealthCheck.TYPE(), address(singleCollatHealthCheck));
        riskEngine.setHealthCheck(singleDebtHealthCheck.TYPE(), address(singleDebtHealthCheck));

        // clean up
        positionManager.transferOwnership(owner);
        riskEngine.transferOwnership(owner);
        poolFactory.transferOwnership(owner);
    }
}
