// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {PoolFactory} from "src/PoolFactory.sol";
import {Pool} from "src/Pool.sol";
import {RiskEngine} from "src/RiskEngine.sol";
import {PositionManager} from "src/PositionManager.sol";
import {OWNER} from "src/Constants.sol";

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
    PositionManager public positionManager;
    RiskEngine public riskEngine;
    PoolFactory public poolFactory;


    /// @notice uses values from the constants file in src/
    function run() public {
        run(OWNER);
    }

    function run(address owner) public {
        positionManager = new PositionManager();
        riskEngine = new RiskEngine();
        poolFactory = new PoolFactory(address(positionManager));

        singleCollatHealthCheck = new SingleCollatHealthCheck();
        singleDebtHealthCheck = new SingleDebtHealthCheck();

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