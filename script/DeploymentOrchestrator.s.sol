// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { BaseScript } from "./BaseScript.s.sol";

import { Deploy } from "./Deploy.s.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
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
 * @title DeploymentOrchestrator
 * @notice One-click deployment script for the entire protocol including:
 * 1. Core protocol deployment
 * 2. IRM deployment and registration
 * 3. Oracle registration
 * 4. Pool initialization
 * 5. LTV setting
 * 6. SuperPool deployment
 * 7. Pool cap setting
 * 8. Asset whitelisting
 */
contract DeploymentOrchestrator is BaseScript {
    // Max uint256 value for unlimited caps
    uint256 internal constant _MAX_UINT256 =
        115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_935;

    // Deployed protocol contracts
    address public registry;
    address public pool;
    address public riskEngine;
    address public riskModule;
    address public positionManager;
    address public superPoolFactory;
    address public positionBeacon;
    address public superPoolLens;
    address public portfolioLens;

    // Deployed interest rate model
    address public kinkedRateModel;
    bytes32 public kinkedRateModelKey = 0x049334b29cf15884b80a41f637935fc255f34ee10a5529fa58dd36d6f35e4333;

    // Pool variables
    uint256 public poolId;
    address public deployedSuperPool;

    // Config variables
    struct OrchestratorConfig {
        // Protocol deployment params
        address owner;
        address proxyAdmin;
        address feeRecipient;
        uint256 minLtv;
        uint256 maxLtv;
        uint256 minDebt;
        uint256 minBorrow;
        uint256 liquidationFee;
        uint256 liquidationDiscount;
        uint256 badDebtLiquidationDiscount;
        uint256 defaultInterestFee;
        uint256 defaultOriginationFee;
        // KinkedRateModel parameters
        uint256 minRate;
        uint256 slope1;
        uint256 slope2;
        uint256 optimalUtil;
        // Assets
        address borrowAsset;
        address borrowAssetOracle;
        address collateralAsset;
        address collateralAssetOracle;
        // Borrow asset pool parameters
        uint256 borrowAssetPoolCap;
        uint256 borrowAssetBorrowCap;
        uint256 borrowAssetInitialDeposit;
        // SuperPool parameters
        uint256 superPoolCap;
        uint256 superPoolFee;
        uint256 superPoolInitialDeposit;
        string superPoolName;
        string superPoolSymbol;
        // LTV settings
        uint256 collateralLtv;
    }

    OrchestratorConfig internal _config;

    // Expose internal methods and config values for testing
    function _deployProtocol() public {
        _deployProtocolInternal();
    }

    function _deployAndRegisterIRM() public {
        _deployAndRegisterIRMInternal();
    }

    function _registerOracles() public {
        _registerOraclesInternal();
    }

    function _initializePool() public {
        _initializePoolInternal();
    }

    function _setLtv() public {
        _setLtvInternal();
    }

    function _deploySuperPool() public {
        _deploySuperPoolInternal();
    }

    function _getConfigCollateralAsset() public view returns (address) {
        return _config.collateralAsset;
    }

    function _getConfigSuperPoolInitialDeposit() public view returns (uint256) {
        return _config.superPoolInitialDeposit;
    }

    function run() public virtual {
        _fetchConfig();
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // Step 1: Deploy core protocol
        _deployProtocolInternal();

        // Step 2: Deploy and register IRM
        _deployAndRegisterIRMInternal();

        // Step 3: Register oracles
        _registerOraclesInternal();

        // Step 4: Initialize pool
        _initializePoolInternal();

        // Step 5: Set LTV
        _setLtvInternal();

        // Step 6: Deploy SuperPool
        _deploySuperPoolInternal();

        // Step 7: Add pool to SuperPool
        _setPoolCap();

        // Step 8: Whitelist assets in the PositionManager
        _whitelistAssets();

        // Generate logs
        _generateLogs();

        vm.stopBroadcast();
    }

    /**
     * @dev Parses scientific notation strings like "0.2e18" into uint256
     * @param notation The scientific notation string
     * @return The parsed uint256 value
     */
    function _parseScientificNotation(string memory notation) internal pure returns (uint256) {
        // Handle "max" special value
        bytes memory notationBytes = bytes(notation);
        if (notationBytes.length == 3 && notationBytes[0] == "m" && notationBytes[1] == "a" && notationBytes[2] == "x")
        {
            return _MAX_UINT256;
        }

        // Find 'e' position
        int256 ePos = -1;
        for (uint256 i = 0; i < notationBytes.length; i++) {
            if (notationBytes[i] == "e" || notationBytes[i] == "E") {
                ePos = int256(i);
                break;
            }
        }

        // If no 'e' found, try to parse as regular uint
        if (ePos == -1) return vm.parseUint(notation);

        // Extract the coefficient and exponent parts
        string memory coeffStr = _substring(notation, 0, uint256(ePos));
        string memory expStr = _substring(notation, uint256(ePos) + 1, notationBytes.length - uint256(ePos) - 1);

        // Parse coefficient as decimal
        uint256 decimalPos = _findDecimalPoint(coeffStr);
        uint256 decimals = 0;
        uint256 coefficient;

        if (decimalPos != type(uint256).max) {
            // Has decimal point, count decimals and remove the point
            decimals = bytes(coeffStr).length - decimalPos - 1;
            string memory intPart = _substring(coeffStr, 0, decimalPos);
            string memory decPart = _substring(coeffStr, decimalPos + 1, bytes(coeffStr).length - decimalPos - 1);

            if (bytes(intPart).length == 0) intPart = "0";
            coefficient = vm.parseUint(string(abi.encodePacked(intPart, decPart)));
        } else {
            // No decimal point
            coefficient = vm.parseUint(coeffStr);
        }

        // Parse exponent
        uint256 exponent = vm.parseUint(expStr);

        // Apply decimals adjustment
        if (decimals > 0) exponent = exponent - decimals;

        // Calculate the final value: coefficient * 10^exponent
        return coefficient * (10 ** exponent);
    }

    /**
     * @dev Finds the position of the decimal point in a string
     * @param str The string to search
     * @return The position of the decimal point, or type(uint256).max if not found
     */
    function _findDecimalPoint(string memory str) internal pure returns (uint256) {
        bytes memory strBytes = bytes(str);

        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == ".") return i;
        }

        return type(uint256).max;
    }

    /**
     * @dev Extracts a substring from a string
     * @param str The input string
     * @param startIndex The starting index
     * @param length The length of the substring
     * @return The extracted substring
     */
    function _substring(string memory str, uint256 startIndex, uint256 length) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        require(startIndex + length <= strBytes.length, "Substring out of bounds");

        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = strBytes[startIndex + i];
        }

        return string(result);
    }

    function _fetchConfig() internal {
        string memory configJson = getConfig();

        _fetchProtocolParams(configJson);
        _fetchKinkedRateModelParams(configJson);
        _fetchAssetParams(configJson);
        _fetchBorrowPoolParams(configJson);
        _fetchSuperPoolParams(configJson);
        _fetchLtvSettings(configJson);

        // Print config values for verification
        console2.log("Configuration loaded:");
        console2.log("minLtv:", _config.minLtv);
        console2.log("maxLtv:", _config.maxLtv);
        console2.log("borrowAssetPoolCap:", _config.borrowAssetPoolCap);
        console2.log("collateralLtv:", _config.collateralLtv);
    }

    function _fetchProtocolParams(string memory configJson) internal {
        // Protocol deployment params
        _config.owner = vm.parseJsonAddress(configJson, "$.DeploymentOrchestrator.protocolParams.owner");
        _config.proxyAdmin = vm.parseJsonAddress(configJson, "$.DeploymentOrchestrator.protocolParams.proxyAdmin");
        _config.feeRecipient = vm.parseJsonAddress(configJson, "$.DeploymentOrchestrator.protocolParams.feeRecipient");

        // Parse scientific notation values
        string memory minLtvStr = vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.minLtv");
        _config.minLtv = _parseScientificNotation(minLtvStr);

        string memory maxLtvStr = vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.maxLtv");
        _config.maxLtv = _parseScientificNotation(maxLtvStr);

        string memory minDebtStr = vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.minDebt");
        _config.minDebt = _parseScientificNotation(minDebtStr);

        string memory minBorrowStr = vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.minBorrow");
        _config.minBorrow = _parseScientificNotation(minBorrowStr);

        string memory liquidationFeeStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.liquidationFee");
        _config.liquidationFee = _parseScientificNotation(liquidationFeeStr);

        string memory liquidationDiscountStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.liquidationDiscount");
        _config.liquidationDiscount = _parseScientificNotation(liquidationDiscountStr);

        string memory badDebtLiquidationDiscountStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.badDebtLiquidationDiscount");
        _config.badDebtLiquidationDiscount = _parseScientificNotation(badDebtLiquidationDiscountStr);

        string memory defaultInterestFeeStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.defaultInterestFee");
        _config.defaultInterestFee = _parseScientificNotation(defaultInterestFeeStr);

        string memory defaultOriginationFeeStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.defaultOriginationFee");
        _config.defaultOriginationFee = _parseScientificNotation(defaultOriginationFeeStr);
    }

    function _fetchKinkedRateModelParams(string memory configJson) internal {
        // KinkedRateModel parameters
        string memory minRateStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.kinkedRateModelParams.minRate");
        _config.minRate = _parseScientificNotation(minRateStr);

        string memory slope1Str =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.kinkedRateModelParams.slope1");
        _config.slope1 = _parseScientificNotation(slope1Str);

        string memory slope2Str =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.kinkedRateModelParams.slope2");
        _config.slope2 = _parseScientificNotation(slope2Str);

        string memory optimalUtilStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.kinkedRateModelParams.optimalUtil");
        _config.optimalUtil = _parseScientificNotation(optimalUtilStr);
    }

    function _fetchAssetParams(string memory configJson) internal {
        // Assets
        _config.borrowAsset = vm.parseJsonAddress(configJson, "$.DeploymentOrchestrator.assetParams.borrowAsset");
        _config.borrowAssetOracle =
            vm.parseJsonAddress(configJson, "$.DeploymentOrchestrator.assetParams.borrowAssetOracle");
        _config.collateralAsset =
            vm.parseJsonAddress(configJson, "$.DeploymentOrchestrator.assetParams.collateralAsset");
        _config.collateralAssetOracle =
            vm.parseJsonAddress(configJson, "$.DeploymentOrchestrator.assetParams.collateralAssetOracle");
    }

    function _fetchBorrowPoolParams(string memory configJson) internal {
        // Borrow asset pool parameters
        string memory borrowAssetPoolCapStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.borrowPoolParams.borrowAssetPoolCap");
        _config.borrowAssetPoolCap = _parseScientificNotation(borrowAssetPoolCapStr);

        string memory borrowAssetBorrowCapStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.borrowPoolParams.borrowAssetBorrowCap");
        _config.borrowAssetBorrowCap = _parseScientificNotation(borrowAssetBorrowCapStr);

        string memory borrowAssetInitialDepositStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.borrowPoolParams.borrowAssetInitialDeposit");
        _config.borrowAssetInitialDeposit = _parseScientificNotation(borrowAssetInitialDepositStr);
    }

    function _fetchSuperPoolParams(string memory configJson) internal {
        // SuperPool parameters
        string memory superPoolCapStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.superPoolParams.superPoolCap");
        _config.superPoolCap = _parseScientificNotation(superPoolCapStr);

        string memory superPoolFeeStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.superPoolParams.superPoolFee");
        _config.superPoolFee = _parseScientificNotation(superPoolFeeStr);

        string memory superPoolInitialDepositStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.superPoolParams.superPoolInitialDeposit");
        _config.superPoolInitialDeposit = _parseScientificNotation(superPoolInitialDepositStr);

        _config.superPoolName = vm.parseJsonString(configJson, "$.DeploymentOrchestrator.superPoolParams.superPoolName");
        _config.superPoolSymbol =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.superPoolParams.superPoolSymbol");
    }

    function _fetchLtvSettings(string memory configJson) internal {
        // LTV settings
        string memory collateralLtvStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.ltvSettings.collateralLtv");
        _config.collateralLtv = _parseScientificNotation(collateralLtvStr);
    }

    function _deployProtocolInternal() internal {
        console2.log("1. Deploying core protocol...");

        Deploy protocol = new Deploy();

        Deploy.DeployParams memory params = Deploy.DeployParams({
            owner: _config.owner,
            proxyAdmin: _config.proxyAdmin,
            feeRecipient: _config.feeRecipient,
            minLtv: _config.minLtv,
            maxLtv: _config.maxLtv,
            minDebt: _config.minDebt,
            minBorrow: _config.minBorrow,
            liquidationFee: _config.liquidationFee,
            liquidationDiscount: _config.liquidationDiscount,
            badDebtLiquidationDiscount: _config.badDebtLiquidationDiscount,
            defaultInterestFee: _config.defaultInterestFee,
            defaultOriginationFee: _config.defaultOriginationFee
        });

        protocol.runWithParams(params);

        // Store deployed contract addresses
        registry = address(protocol.registry());
        pool = address(protocol.pool());
        riskEngine = address(protocol.riskEngine());
        riskModule = address(protocol.riskModule());
        positionManager = address(protocol.positionManager());
        superPoolFactory = address(protocol.superPoolFactory());
        positionBeacon = address(protocol.positionBeacon());
        superPoolLens = address(protocol.superPoolLens());
        portfolioLens = address(protocol.portfolioLens());

        console2.log("Core protocol deployed");
        console2.log("Registry:", registry);
        console2.log("Pool:", pool);
        console2.log("RiskEngine:", riskEngine);
    }

    function _deployAndRegisterIRMInternal() internal {
        console2.log("2. Deploying and registering IRM...");

        // Deploy KinkedRateModel
        kinkedRateModel =
            address(new KinkedRateModel(_config.minRate, _config.slope1, _config.slope2, _config.optimalUtil));
        console2.log("KinkedRateModel deployed:", kinkedRateModel);

        // Register KinkedRateModel in Registry
        Registry(registry).setRateModel(kinkedRateModelKey, kinkedRateModel);
        console2.log("KinkedRateModel registered with key:", vm.toString(kinkedRateModelKey));
    }

    function _registerOraclesInternal() internal {
        console2.log("3. Registering oracles...");

        // Set oracles for both assets
        RiskEngine(riskEngine).setOracle(_config.borrowAsset, _config.borrowAssetOracle);
        console2.log("Oracle set for borrowAsset:", _config.borrowAsset, "=>", _config.borrowAssetOracle);

        RiskEngine(riskEngine).setOracle(_config.collateralAsset, _config.collateralAssetOracle);
        console2.log("Oracle set for collateralAsset:", _config.collateralAsset, "=>", _config.collateralAssetOracle);
    }

    function _initializePoolInternal() internal {
        console2.log("4. Initializing pool...");

        // Approve tokens for initial deposit
        IERC20(_config.borrowAsset).approve(pool, _config.borrowAssetInitialDeposit);

        // Initialize pool for the borrow asset
        poolId = Pool(pool).initializePool(
            _config.owner,
            _config.borrowAsset,
            kinkedRateModelKey,
            _config.borrowAssetPoolCap,
            _config.borrowAssetBorrowCap,
            _config.borrowAssetInitialDeposit
        );

        console2.log("Pool initialized with ID:", poolId);
    }

    function _setLtvInternal() internal {
        console2.log("5. Setting LTV...");

        // Request and accept LTV update for the collateral asset
        RiskEngine(riskEngine).requestLtvUpdate(poolId, _config.collateralAsset, _config.collateralLtv);

        // Since this is a first-time LTV setting, we can accept it immediately without timelock
        if (RiskEngine(riskEngine).ltvFor(poolId, _config.collateralAsset) == 0) {
            RiskEngine(riskEngine).acceptLtvUpdate(poolId, _config.collateralAsset);
            console2.log("LTV set for collateralAsset in pool:", poolId, _config.collateralLtv);
        }
    }

    function _deploySuperPoolInternal() internal {
        console2.log("6. Deploying SuperPool...");

        // Approve tokens for initial deposit
        console2.log("Approving borrow asset for SuperPool Factory:", _config.borrowAsset);
        console2.log("Approval amount:", _config.superPoolInitialDeposit);
        console2.log("SuperPoolFactory address:", superPoolFactory);

        // Check balance before approval
        uint256 balance = IERC20(_config.borrowAsset).balanceOf(address(this));
        console2.log("Balance of borrow asset before approval:", balance);

        IERC20(_config.borrowAsset).approve(superPoolFactory, _config.superPoolInitialDeposit);

        // Deploy SuperPool for the collateral asset
        console2.log("Deploying SuperPool with parameters:");
        console2.log("- Owner:", _config.owner);
        console2.log("- Borrow Asset:", _config.borrowAsset);
        console2.log("- Fee Recipient:", _config.feeRecipient);
        console2.log("- SuperPool Fee:", _config.superPoolFee);
        console2.log("- SuperPool Cap:", _config.superPoolCap);
        console2.log("- Initial Deposit:", _config.superPoolInitialDeposit);
        console2.log("- Name:", _config.superPoolName);
        console2.log("- Symbol:", _config.superPoolSymbol);

        deployedSuperPool = SuperPoolFactory(superPoolFactory).deploySuperPool(
            _config.owner,
            _config.borrowAsset,
            _config.feeRecipient,
            _config.superPoolFee,
            _config.superPoolCap,
            _config.superPoolInitialDeposit,
            _config.superPoolName,
            _config.superPoolSymbol
        );

        console2.log("SuperPool deployed:", deployedSuperPool);
    }

    function _setPoolCap() internal {
        console2.log("7. Setting pool cap in SuperPool...");

        // Add pool to SuperPool with cap
        SuperPool(deployedSuperPool).addPool(poolId, _config.superPoolCap);

        console2.log("Pool added to SuperPool with cap:", _config.superPoolCap);
    }

    function _whitelistAssets() internal {
        console2.log("8. Whitelisting assets in PositionManager...");

        // Whitelist borrow and collateral assets
        PositionManager(positionManager).toggleKnownAsset(_config.borrowAsset);
        console2.log("Whitelisted borrowAsset:", _config.borrowAsset);

        PositionManager(positionManager).toggleKnownAsset(_config.collateralAsset);
        console2.log("Whitelisted collateralAsset:", _config.collateralAsset);
    }

    function _generateLogs() internal {
        string memory obj = "DeploymentOrchestrator";

        // Core protocol addresses
        vm.serializeAddress(obj, "registry", registry);
        vm.serializeAddress(obj, "pool", pool);
        vm.serializeAddress(obj, "riskEngine", riskEngine);
        vm.serializeAddress(obj, "riskModule", riskModule);
        vm.serializeAddress(obj, "positionManager", positionManager);
        vm.serializeAddress(obj, "superPoolFactory", superPoolFactory);
        vm.serializeAddress(obj, "positionBeacon", positionBeacon);
        vm.serializeAddress(obj, "superPoolLens", superPoolLens);
        vm.serializeAddress(obj, "portfolioLens", portfolioLens);

        // IRM
        vm.serializeAddress(obj, "kinkedRateModel", kinkedRateModel);
        vm.serializeBytes32(obj, "kinkedRateModelKey", kinkedRateModelKey);

        // Pool details
        vm.serializeUint(obj, "poolId", poolId);

        // Asset details
        vm.serializeAddress(obj, "borrowAsset", _config.borrowAsset);
        vm.serializeAddress(obj, "borrowAssetOracle", _config.borrowAssetOracle);
        vm.serializeAddress(obj, "collateralAsset", _config.collateralAsset);
        vm.serializeAddress(obj, "collateralAssetOracle", _config.collateralAssetOracle);

        // SuperPool
        vm.serializeAddress(obj, "superPool", deployedSuperPool);

        // Deployment details
        vm.serializeUint(obj, "chainId", block.chainid);
        string memory json = vm.serializeUint(obj, "timestamp", vm.getBlockTimestamp());

        string memory path =
            string.concat(getLogPathBase(), "DeploymentOrchestrator-", vm.toString(vm.getBlockTimestamp()), ".json");

        vm.writeJson(json, path);
        console2.log("Deployment logs written to:", path);
    }
}
