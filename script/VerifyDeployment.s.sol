// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "./BaseScript.s.sol";

import { Vm, VmSafe } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { Pool } from "src/Pool.sol";
import { PositionManager } from "src/PositionManager.sol";
import { Registry } from "src/Registry.sol";
import { RiskEngine } from "src/RiskEngine.sol";

import { SuperPool } from "src/SuperPool.sol";
import { SuperPoolFactory } from "src/SuperPoolFactory.sol";
import { KinkedRateModel } from "src/irm/KinkedRateModel.sol";

/**
 * @title VerifyDeployment
 * @notice Script to verify that all components of the protocol were deployed correctly
 * Reads the most recent deployment log file and checks that everything is working
 */
contract VerifyDeployment is BaseScript {
    // Verification status struct
    struct VerificationStatus {
        bool registryOk;
        bool poolOk;
        bool riskEngineOk;
        bool riskModuleOk;
        bool positionManagerOk;
        bool superPoolFactoryOk;
        bool positionBeaconOk;
        bool irmOk;
        bool poolInitOk;
        bool ltvSetOk;
        bool superPoolOk;
        bool poolCapSetOk;
        bool assetsWhitelistedOk;
    }

    // Deployed addresses
    address public registry;
    address public pool;
    address public riskEngine;
    address public riskModule;
    address public positionManager;
    address public superPoolFactory;
    address public positionBeacon;
    address public superPoolLens;
    address public portfolioLens;
    address public kinkedRateModel;
    bytes32 public kinkedRateModelKey;
    uint256 public poolId;
    address public superPool;

    // Assets
    address public borrowAsset;
    address public borrowAssetOracle;
    address public collateralAsset;
    address public collateralAssetOracle;
    uint256 public collateralLtv;

    // Overall status
    VerificationStatus public status;

    function run() public {
        // Find most recent deployment log
        VmSafe.DirEntry[] memory dirEntries = vm.readDir(getLogPathBase());
        string memory latestLog = "";
        uint256 latestTimestamp = 0;

        for (uint256 i = 0; i < dirEntries.length; i++) {
            string memory fileName = dirEntries[i].path;

            // Extract just the filename from the path
            bytes memory fileNameBytes = bytes(fileName);
            uint256 fileNameLastSlashPos = 0;
            for (uint256 j = 0; j < fileNameBytes.length; j++) {
                if (fileNameBytes[j] == bytes1("/")) fileNameLastSlashPos = j + 1;
            }

            string memory fileNameOnly = "";
            if (fileNameLastSlashPos < fileNameBytes.length) {
                uint256 nameLength = fileNameBytes.length - fileNameLastSlashPos;
                bytes memory nameBytes = new bytes(nameLength);
                for (uint256 j = 0; j < nameLength; j++) {
                    nameBytes[j] = fileNameBytes[fileNameLastSlashPos + j];
                }
                fileNameOnly = string(nameBytes);
            }

            // Check if file contains DeploymentOrchestrator
            bool isDeploymentOrchestratorLog = false;
            bytes memory deploymentOrchestratorPrefix = bytes("DeploymentOrchestrator-");
            bytes memory fileNameOnlyBytes = bytes(fileNameOnly);

            if (fileNameOnlyBytes.length >= deploymentOrchestratorPrefix.length) {
                isDeploymentOrchestratorLog = true;
                for (uint256 j = 0; j < deploymentOrchestratorPrefix.length; j++) {
                    if (fileNameOnlyBytes[j] != deploymentOrchestratorPrefix[j]) {
                        isDeploymentOrchestratorLog = false;
                        break;
                    }
                }
            }

            if (isDeploymentOrchestratorLog) {
                // Extract timestamp from filename
                uint256 prefixLength = deploymentOrchestratorPrefix.length;
                uint256 suffixLength = 5; // ".json"
                uint256 timestampLength = fileNameOnlyBytes.length - prefixLength - suffixLength;

                bytes memory timestampBytes = new bytes(timestampLength);
                for (uint256 j = 0; j < timestampLength; j++) {
                    timestampBytes[j] = fileNameOnlyBytes[prefixLength + j];
                }

                string memory timestamp = string(timestampBytes);
                uint256 fileTimestamp = vm.parseUint(timestamp);

                if (fileTimestamp > latestTimestamp) {
                    latestTimestamp = fileTimestamp;
                    latestLog = fileName;
                }
            }
        }

        if (bytes(latestLog).length == 0) {
            console2.log("No deployment logs found");
            return;
        }

        // Extract just the filename part for logging
        string memory logFileName = "";
        bytes memory logPathBytes = bytes(latestLog);
        uint256 logPathLastSlashPos = 0;
        for (uint256 j = 0; j < logPathBytes.length; j++) {
            if (logPathBytes[j] == bytes1("/")) logPathLastSlashPos = j + 1;
        }

        if (logPathLastSlashPos < logPathBytes.length) {
            uint256 nameLength = logPathBytes.length - logPathLastSlashPos;
            bytes memory nameBytes = new bytes(nameLength);
            for (uint256 j = 0; j < nameLength; j++) {
                nameBytes[j] = logPathBytes[logPathLastSlashPos + j];
            }
            logFileName = string(nameBytes);
        }

        console2.log("Using log file:", logFileName);
        string memory logContent = vm.readFile(latestLog);

        // Read addresses from log
        registry = vm.parseJsonAddress(logContent, "$.registry");
        pool = vm.parseJsonAddress(logContent, "$.pool");
        riskEngine = vm.parseJsonAddress(logContent, "$.riskEngine");
        riskModule = vm.parseJsonAddress(logContent, "$.riskModule");
        positionManager = vm.parseJsonAddress(logContent, "$.positionManager");
        superPoolFactory = vm.parseJsonAddress(logContent, "$.superPoolFactory");
        positionBeacon = vm.parseJsonAddress(logContent, "$.positionBeacon");
        superPoolLens = vm.parseJsonAddress(logContent, "$.superPoolLens");
        portfolioLens = vm.parseJsonAddress(logContent, "$.portfolioLens");
        kinkedRateModel = vm.parseJsonAddress(logContent, "$.kinkedRateModel");
        kinkedRateModelKey = vm.parseJsonBytes32(logContent, "$.kinkedRateModelKey");
        poolId = vm.parseJsonUint(logContent, "$.poolId");
        superPool = vm.parseJsonAddress(logContent, "$.superPool");

        borrowAsset = vm.parseJsonAddress(logContent, "$.borrowAsset");
        borrowAssetOracle = vm.parseJsonAddress(logContent, "$.borrowAssetOracle");
        collateralAsset = vm.parseJsonAddress(logContent, "$.collateralAsset");
        collateralAssetOracle = vm.parseJsonAddress(logContent, "$.collateralAssetOracle");

        // Start verification
        console2.log("\n=== PROTOCOL DEPLOYMENT VERIFICATION ===");

        // 1. Verify core protocol contracts
        _verifyProtocol();

        // 2. Verify IRM
        _verifyIRM();

        // 3. Verify oracles
        _verifyOracles();

        // 4. Verify pool initialization
        _verifyPool();

        // 5. Verify LTV
        _verifyLTV();

        // 6. Verify SuperPool
        _verifySuperPool();

        // 7. Verify asset whitelisting
        _verifyAssetWhitelisting();

        // Print overall status
        _printStatus();
    }

    function _verifyProtocol() internal {
        console2.log("\n1. Verifying core protocol contracts...");

        // Check registry
        status.registryOk = registry != address(0) && registry.code.length > 0;
        console2.log("Registry:", status.registryOk ? "OK" : "FAIL", registry);

        // Check pool
        status.poolOk = pool != address(0) && pool.code.length > 0;
        console2.log("Pool:", status.poolOk ? "OK" : "FAIL", pool);

        // Check risk engine
        status.riskEngineOk = riskEngine != address(0) && riskEngine.code.length > 0;
        console2.log("RiskEngine:", status.riskEngineOk ? "OK" : "FAIL", riskEngine);

        // Check risk module
        status.riskModuleOk = riskModule != address(0) && riskModule.code.length > 0;
        console2.log("RiskModule:", status.riskModuleOk ? "OK" : "FAIL", riskModule);

        // Check position manager
        status.positionManagerOk = positionManager != address(0) && positionManager.code.length > 0;
        console2.log("PositionManager:", status.positionManagerOk ? "OK" : "FAIL", positionManager);

        // Check SuperPoolFactory
        status.superPoolFactoryOk = superPoolFactory != address(0) && superPoolFactory.code.length > 0;
        console2.log("SuperPoolFactory:", status.superPoolFactoryOk ? "OK" : "FAIL", superPoolFactory);

        // Check position beacon
        status.positionBeaconOk = positionBeacon != address(0) && positionBeacon.code.length > 0;
        console2.log("PositionBeacon:", status.positionBeaconOk ? "OK" : "FAIL", positionBeacon);
    }

    function _verifyIRM() internal {
        console2.log("\n2. Verifying Interest Rate Model...");

        // Check KinkedRateModel deployment
        bool irmDeployed = kinkedRateModel != address(0) && kinkedRateModel.code.length > 0;
        console2.log("KinkedRateModel deployed:", irmDeployed ? "OK" : "FAIL", kinkedRateModel);

        // Check IRM registration
        address registeredIrm = Registry(registry).rateModelFor(kinkedRateModelKey);
        bool irmRegistered = registeredIrm == kinkedRateModel;
        console2.log("KinkedRateModel registered:", irmRegistered ? "OK" : "FAIL");

        status.irmOk = irmDeployed && irmRegistered;
    }

    function _verifyOracles() internal view {
        console2.log("\n3. Verifying Oracles...");

        // Check borrow asset oracle
        address registeredBorrowOracle = RiskEngine(riskEngine).oracleFor(borrowAsset);
        bool borrowOracleOk = registeredBorrowOracle == borrowAssetOracle;
        console2.log("Borrow asset:", borrowAsset);
        console2.log("Borrow asset oracle:", borrowOracleOk ? "OK" : "FAIL", "Address:", borrowAssetOracle);

        // Check collateral asset oracle
        address registeredCollateralOracle = RiskEngine(riskEngine).oracleFor(collateralAsset);
        bool collateralOracleOk = registeredCollateralOracle == collateralAssetOracle;
        console2.log("Collateral asset:", collateralAsset);
        console2.log("Collateral asset oracle:", collateralOracleOk ? "OK" : "FAIL", "Address:", collateralAssetOracle);
    }

    function _verifyPool() internal {
        console2.log("\n4. Verifying Pool Initialization...");

        // Check if pool exists
        address poolOwner = Pool(pool).ownerOf(poolId);
        bool poolExists = poolOwner != address(0);
        console2.log("Pool exists:", poolExists ? "OK" : "FAIL", "ID:", poolId);

        // Check pool asset
        address poolAsset = Pool(pool).getPoolAssetFor(poolId);
        bool correctAsset = poolAsset == borrowAsset;
        console2.log("Pool asset:", correctAsset ? "OK" : "FAIL");

        // Check rate model
        address poolRateModel = Pool(pool).getRateModelFor(poolId);
        bool correctRateModel = poolRateModel == kinkedRateModel;
        console2.log("Pool rate model:", correctRateModel ? "OK" : "FAIL");

        status.poolInitOk = poolExists && correctAsset && correctRateModel;
    }

    function _verifyLTV() internal {
        console2.log("\n5. Verifying LTV Settings...");

        // Check LTV for collateral asset
        uint256 ltv = RiskEngine(riskEngine).ltvFor(poolId, collateralAsset);
        bool ltvSet = ltv > 0;
        console2.log("Collateral asset:", collateralAsset);
        console2.log("Collateral LTV set:", ltvSet ? "OK" : "FAIL", "Value:", ltv);

        // Also check LTV for borrow asset (should be 0)
        uint256 borrowLtv = RiskEngine(riskEngine).ltvFor(poolId, borrowAsset);
        console2.log("Borrow asset:", borrowAsset);
        console2.log("Borrow asset LTV value:", borrowLtv);

        status.ltvSetOk = ltvSet;
    }

    function _verifySuperPool() internal {
        console2.log("\n6. Verifying SuperPool...");

        // Check SuperPool deployment
        bool superPoolDeployed = superPool != address(0) && superPool.code.length > 0;
        console2.log("SuperPool deployed:", superPoolDeployed ? "OK" : "FAIL", superPool);

        if (superPoolDeployed) {
            // Check SuperPool asset
            address superPoolAsset = SuperPool(superPool).asset();
            bool correctSuperPoolAsset = superPoolAsset == borrowAsset;
            console2.log("SuperPool asset:", correctSuperPoolAsset ? "OK" : "FAIL");

            // Check if pool is in SuperPool
            uint256 poolCap = SuperPool(superPool).poolCapFor(poolId);
            bool poolInSuperPool = poolCap > 0;
            console2.log("Pool added to SuperPool:", poolInSuperPool ? "OK" : "FAIL", "Cap:", poolCap);

            status.superPoolOk = superPoolDeployed && correctSuperPoolAsset;
            status.poolCapSetOk = poolInSuperPool;
        }
    }

    function _verifyAssetWhitelisting() internal {
        console2.log("\n7. Verifying Asset Whitelisting...");

        // Check if borrowAsset is whitelisted
        bool borrowAssetWhitelisted = PositionManager(positionManager).isKnownAsset(borrowAsset);
        console2.log("Borrow asset whitelisted:", borrowAssetWhitelisted ? "OK" : "FAIL");

        // Check if collateralAsset is whitelisted
        bool collateralAssetWhitelisted = PositionManager(positionManager).isKnownAsset(collateralAsset);
        console2.log("Collateral asset whitelisted:", collateralAssetWhitelisted ? "OK" : "FAIL");

        status.assetsWhitelistedOk = borrowAssetWhitelisted && collateralAssetWhitelisted;
    }

    function _printStatus() internal view {
        console2.log("\n=== DEPLOYMENT VERIFICATION SUMMARY ===");
        console2.log("Core Protocol:", _getAllCoreOk() ? "PASS" : "FAIL");
        console2.log("IRM:", status.irmOk ? "PASS" : "FAIL");
        console2.log("Pool Initialization:", status.poolInitOk ? "PASS" : "FAIL");
        console2.log("LTV Settings:", status.ltvSetOk ? "PASS" : "FAIL");
        console2.log("SuperPool:", status.superPoolOk ? "PASS" : "FAIL");
        console2.log("Pool Cap in SuperPool:", status.poolCapSetOk ? "PASS" : "FAIL");
        console2.log("Asset Whitelisting:", status.assetsWhitelistedOk ? "PASS" : "FAIL");

        bool allOk = _getAllCoreOk() && status.irmOk && status.poolInitOk && status.ltvSetOk && status.superPoolOk
            && status.poolCapSetOk && status.assetsWhitelistedOk;

        console2.log("\nOVERALL STATUS:", allOk ? "DEPLOYMENT SUCCESSFUL" : "DEPLOYMENT ISSUES DETECTED");

        if (!allOk) console2.log("\nPlease check the logs above to identify and fix any issues.");
    }

    function _getAllCoreOk() internal view returns (bool) {
        return status.registryOk && status.poolOk && status.riskEngineOk && status.riskModuleOk
            && status.positionManagerOk && status.superPoolFactoryOk && status.positionBeaconOk;
    }
}
