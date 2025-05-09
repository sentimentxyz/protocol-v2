// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { BaseScript } from "./BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { Pool } from "src/Pool.sol";

import { PositionManager } from "src/PositionManager.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { SuperPool } from "src/SuperPool.sol";
import { SuperPoolFactory } from "src/SuperPoolFactory.sol";

/**
 * @title StrategyDeployer
 * @notice Strategy deployment script with stack optimization
 */
contract StrategyDeployer is BaseScript {
    // Core addresses
    address public pool;
    address public riskEngine;
    address public superPoolFactory;
    address public positionManager;

    // Pool params
    address public poolOwner;
    address public poolAsset;
    bytes32 public rateModelKey;
    uint256 public poolDepositCap;
    uint256 public poolBorrowCap;
    uint256 public poolInitialDeposit;

    // LTV params (optional)
    bool public needSetLtv;
    address public collateralAsset;
    uint256 public collateralLtv;

    // SuperPool params
    address public superPoolOwner;
    address public feeRecipient;
    uint256 public superPoolFee;
    uint256 public superPoolCap;
    uint256 public superPoolDeposit;
    string public superPoolName;
    string public superPoolSymbol;

    // Pool cap
    uint256 public poolCapInSuperPool;

    // Results
    uint256 public poolId;
    address public deployedSuperPool;

    function run() public {
        // Load all configurations
        loadBasicConfig();
        loadPoolConfig();
        loadSuperPoolConfig();

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // Execute deployment steps
        executePoolInitialization();

        if (needSetLtv) executeSetLtv();

        executeSuperPoolDeployment();
        executePoolCapSetting();

        // Log results and save to file
        logResults();
        createLogFile();

        vm.stopBroadcast();
    }

    // Step 1: Initialize the pool
    function executePoolInitialization() internal {
        console2.log("Initializing pool...");
        IERC20(poolAsset).approve(pool, poolInitialDeposit);
        poolId = Pool(pool).initializePool(
            poolOwner, poolAsset, rateModelKey, poolDepositCap, poolBorrowCap, poolInitialDeposit
        );
        console2.log("Pool ID: ", poolId);
    }

    // Step 2: Set LTV if needed
    function executeSetLtv() internal {
        // Check prerequisites
        validateAsset();

        // Request and accept LTV update
        console2.log("Setting LTV...");
        RiskEngine(riskEngine).requestLtvUpdate(poolId, collateralAsset, collateralLtv);

        if (RiskEngine(riskEngine).ltvFor(poolId, collateralAsset) == 0) {
            RiskEngine(riskEngine).acceptLtvUpdate(poolId, collateralAsset);
            console2.log("LTV set successfully");
        }
    }

    // Step 3: Deploy the SuperPool
    function executeSuperPoolDeployment() internal {
        console2.log("Deploying SuperPool...");
        IERC20(poolAsset).approve(superPoolFactory, superPoolDeposit);
        deployedSuperPool = SuperPoolFactory(superPoolFactory).deploySuperPool(
            superPoolOwner,
            poolAsset,
            feeRecipient,
            superPoolFee,
            superPoolCap,
            superPoolDeposit,
            superPoolName,
            superPoolSymbol
        );
        console2.log("SuperPool: ", deployedSuperPool);
    }

    // Step 4: Set the pool cap
    function executePoolCapSetting() internal {
        console2.log("Setting pool cap...");
        SuperPool(deployedSuperPool).addPool(poolId, poolCapInSuperPool);
    }

    // Log deployment results
    function logResults() internal view {
        console2.log("Strategy deployed:");
        console2.log("  Pool ID: ", poolId);
        console2.log("  SuperPool: ", deployedSuperPool);
    }

    // Load basic configuration (core addresses)
    function loadBasicConfig() internal {
        string memory config = getConfig();
        pool = vm.parseJsonAddress(config, "$.StrategyDeployer.pool");
        riskEngine = vm.parseJsonAddress(config, "$.StrategyDeployer.riskEngine");
        superPoolFactory = vm.parseJsonAddress(config, "$.StrategyDeployer.superPoolFactory");
        positionManager = vm.parseJsonAddress(config, "$.StrategyDeployer.positionManager");

        // LTV toggle
        needSetLtv = vm.parseJsonBool(config, "$.StrategyDeployer.needSetLtv");
    }

    // Load pool configuration parameters
    function loadPoolConfig() internal {
        string memory config = getConfig();
        poolOwner = vm.parseJsonAddress(config, "$.StrategyDeployer.poolOwner");
        poolAsset = vm.parseJsonAddress(config, "$.StrategyDeployer.poolAsset");
        rateModelKey = vm.parseJsonBytes32(config, "$.StrategyDeployer.rateModelKey");
        poolDepositCap = vm.parseJsonUint(config, "$.StrategyDeployer.poolDepositCap");
        poolBorrowCap = vm.parseJsonUint(config, "$.StrategyDeployer.poolBorrowCap");
        poolInitialDeposit = vm.parseJsonUint(config, "$.StrategyDeployer.poolInitialDepositAmt");

        // LTV params if needed
        if (needSetLtv) {
            collateralAsset = vm.parseJsonAddress(config, "$.StrategyDeployer.collateralAsset");
            collateralLtv = vm.parseJsonUint(config, "$.StrategyDeployer.collateralLtv");
        }
    }

    // Load SuperPool configuration parameters
    function loadSuperPoolConfig() internal {
        string memory config = getConfig();
        superPoolOwner = vm.parseJsonAddress(config, "$.StrategyDeployer.superPoolOwner");
        feeRecipient = vm.parseJsonAddress(config, "$.StrategyDeployer.feeRecipient");
        superPoolFee = vm.parseJsonUint(config, "$.StrategyDeployer.superPoolFee");
        superPoolCap = vm.parseJsonUint(config, "$.StrategyDeployer.superPoolCap");
        superPoolDeposit = vm.parseJsonUint(config, "$.StrategyDeployer.superPoolInitialDepositAmt");
        superPoolName = vm.parseJsonString(config, "$.StrategyDeployer.superPoolName");
        superPoolSymbol = vm.parseJsonString(config, "$.StrategyDeployer.superPoolSymbol");

        // Pool cap in SuperPool
        poolCapInSuperPool = vm.parseJsonUint(config, "$.StrategyDeployer.poolCapInSuperPool");
    }

    // Validate collateral asset
    function validateAsset() internal view {
        console2.log("Validating collateral asset...");

        // Verify asset is known
        bool isKnown = PositionManager(positionManager).isKnownAsset(collateralAsset);
        require(isKnown, "Collateral asset not known");

        // Verify oracle exists
        address oracle = RiskEngine(riskEngine).oracleFor(collateralAsset);
        require(oracle != address(0), "No oracle for collateral");
    }

    // Create log file with minimal operations
    function createLogFile() internal {
        string memory logPath =
            string.concat(getLogPathBase(), "StrategyDeployer-", vm.toString(block.timestamp), ".json");

        string memory logData = string.concat(
            "{\n",
            '  "poolId": "',
            vm.toString(poolId),
            '",\n',
            '  "superPool": "',
            vm.toString(deployedSuperPool),
            '"\n',
            "}"
        );

        vm.writeFile(logPath, logData);
    }
}
