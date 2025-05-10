// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { BaseScript } from "./BaseScript.s.sol";

import { Deploy } from "./Deploy.s.sol";

import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { Pool } from "src/Pool.sol";
import { Position } from "src/Position.sol";
import { PositionManager } from "src/PositionManager.sol";
import { Registry } from "src/Registry.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { RiskModule } from "src/RiskModule.sol";

import { SuperPool } from "src/SuperPool.sol";
import { SuperPoolFactory } from "src/SuperPoolFactory.sol";
import { KinkedRateModel } from "src/irm/KinkedRateModel.sol";

import { PortfolioLens } from "src/lens/PortfolioLens.sol";
import { SuperPoolLens } from "src/lens/SuperPoolLens.sol";

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
    address public poolImpl;
    address public riskEngine;
    address public riskModule;
    address public positionManager;
    address public positionManagerImpl;
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

    // Config variables - split into separate structs to reduce stack usage
    // Protocol parameters
    struct ProtocolParams {
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
    }

    // KinkedRateModel parameters
    struct RateModelParams {
        uint256 minRate;
        uint256 slope1;
        uint256 slope2;
        uint256 optimalUtil;
    }

    // Asset parameters
    struct AssetParams {
        address borrowAsset;
        address borrowAssetOracle;
        address collateralAsset;
        address collateralAssetOracle;
    }

    // Borrow pool parameters
    struct BorrowPoolParams {
        uint256 borrowAssetPoolCap;
        uint256 borrowAssetBorrowCap;
        uint256 borrowAssetInitialDeposit;
    }

    // SuperPool parameters
    struct SuperPoolParams {
        uint256 superPoolCap;
        uint256 superPoolFee;
        uint256 superPoolInitialDeposit;
        string superPoolName;
        string superPoolSymbol;
    }

    // LTV settings
    struct LtvSettings {
        uint256 collateralLtv;
    }

    // Storage for each configuration section
    ProtocolParams internal _protocolParams;
    RateModelParams internal _rateModelParams;
    AssetParams internal _assetParams;
    BorrowPoolParams internal _borrowPoolParams;
    SuperPoolParams internal _superPoolParams;
    LtvSettings internal _ltvSettings;

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
        return _assetParams.collateralAsset;
    }

    function _getConfigSuperPoolInitialDeposit() public view returns (uint256) {
        return _superPoolParams.superPoolInitialDeposit;
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

        // Step 7: Set the pool's cap in the SuperPool
        _setPoolCap();

        // Step 8: Whitelist assets
        _whitelistAssets();

        // Transfer ownership at the end when everything is done
        RiskEngine(riskEngine).transferOwnership(_protocolParams.owner);
        Registry(registry).transferOwnership(_protocolParams.owner);

        // Log deployment details
        _generateLogs();

        vm.stopBroadcast();
    }

    function _generateLogs() internal {
        console2.log("Logging deployment details...");

        // Console logs
        _logToConsole();

        // Create log files
        _createLogFiles();
    }

    // Separate function for creating log files
    function _createLogFiles() internal {
        // Create log directory if it doesn't exist
        string memory logDir = getLogPathBase();
        string memory mkdirCmd = string.concat("mkdir -p ", logDir);
        string[] memory mkdirArgs = new string[](3);
        mkdirArgs[0] = "bash";
        mkdirArgs[1] = "-c";
        mkdirArgs[2] = mkdirCmd;
        vm.ffi(mkdirArgs);

        // Generate log data
        string memory logJson = _generateLogJson();

        // Write log files
        string memory chainIdStr = vm.toString(block.chainid);
        string memory timestampStr = vm.toString(vm.getBlockTimestamp());

        // Main log file
        string memory logFilename = string.concat(logDir, "deployment_", chainIdStr, "_", timestampStr, ".json");
        vm.writeFile(logFilename, logJson);

        // Latest log file
        string memory latestLogFilename = string.concat(logDir, "latest_", chainIdStr, ".json");
        vm.writeFile(latestLogFilename, logJson);

        console2.log("Logs saved to:", logFilename);
        console2.log("Latest logs symlink:", latestLogFilename);
    }

    // Generate log JSON without nested string concatenations
    function _generateLogJson() internal view returns (string memory) {
        string memory chainIdStr = vm.toString(block.chainid);
        string memory timestampStr = vm.toString(vm.getBlockTimestamp());

        // Build JSON in parts to reduce stack pressure
        string memory part1 = string.concat(
            "{\n",
            '  "chainId": "',
            chainIdStr,
            '",\n',
            '  "timestamp": "',
            timestampStr,
            '",\n',
            '  "registry": "',
            vm.toString(registry),
            '",\n',
            '  "pool": "',
            vm.toString(pool),
            '",\n',
            '  "poolImpl": "',
            vm.toString(poolImpl),
            '",\n'
        );

        string memory part2 = string.concat(
            '  "riskEngine": "',
            vm.toString(riskEngine),
            '",\n',
            '  "riskModule": "',
            vm.toString(riskModule),
            '",\n',
            '  "positionManager": "',
            vm.toString(positionManager),
            '",\n',
            '  "positionManagerImpl": "',
            vm.toString(positionManagerImpl),
            '",\n',
            '  "superPoolFactory": "',
            vm.toString(superPoolFactory),
            '",\n'
        );

        string memory part3 = string.concat(
            '  "positionBeacon": "',
            vm.toString(positionBeacon),
            '",\n',
            '  "superPoolLens": "',
            vm.toString(superPoolLens),
            '",\n',
            '  "portfolioLens": "',
            vm.toString(portfolioLens),
            '",\n',
            '  "kinkedRateModel": "',
            vm.toString(kinkedRateModel),
            '",\n',
            '  "kinkedRateModelKey": "',
            vm.toString(kinkedRateModelKey),
            '",\n'
        );

        string memory part4 = string.concat(
            '  "poolId": "',
            vm.toString(poolId),
            '",\n',
            '  "superPool": "',
            vm.toString(deployedSuperPool),
            '",\n',
            '  "borrowAsset": "',
            vm.toString(_assetParams.borrowAsset),
            '",\n',
            '  "borrowAssetOracle": "',
            vm.toString(_assetParams.borrowAssetOracle),
            '",\n'
        );

        string memory part5 = string.concat(
            '  "collateralAsset": "',
            vm.toString(_assetParams.collateralAsset),
            '",\n',
            '  "collateralAssetOracle": "',
            vm.toString(_assetParams.collateralAssetOracle),
            '"\n',
            "}\n"
        );

        // Combine all parts
        return string.concat(part1, part2, part3, part4, part5);
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

        // Try to parse as regular uint if there's no 'e'
        bool hasE = false;
        uint256 ePosition = 0;

        // Find 'e' position
        for (uint256 i = 0; i < notationBytes.length; i++) {
            if (notationBytes[i] == "e" || notationBytes[i] == "E") {
                hasE = true;
                ePosition = i;
                break;
            }
        }

        // If no 'e' found, try to parse as regular uint
        if (!hasE) return vm.parseUint(notation);

        // Handle scientific notation
        return _parseWithExponent(notationBytes, ePosition);
    }

    // Helper function to reduce stack depth by splitting function logic
    function _parseWithExponent(bytes memory notationBytes, uint256 ePosition) internal pure returns (uint256) {
        // Extract coefficient
        string memory coeffStr = "";
        {
            bytes memory result = new bytes(ePosition);
            for (uint256 i = 0; i < ePosition; i++) {
                result[i] = notationBytes[i];
            }
            coeffStr = string(result);
        }

        // Extract exponent
        string memory expStr = "";
        {
            uint256 expLen = notationBytes.length - ePosition - 1;
            bytes memory result = new bytes(expLen);
            for (uint256 i = 0; i < expLen; i++) {
                result[i] = notationBytes[ePosition + 1 + i];
            }
            expStr = string(result);
        }

        // Handle the coefficient which may have decimal point
        uint256 coefficient;

        // Check for decimal point in coefficient
        bytes memory coeffBytes = bytes(coeffStr);
        for (uint256 i = 0; i < coeffBytes.length; i++) {
            if (coeffBytes[i] == ".") {
                // Process as decimal
                return _handleDecimalCoefficient(coeffStr, i, expStr);
            }
        }

        // No decimal point in coefficient
        coefficient = vm.parseUint(coeffStr);
        uint256 exponent = vm.parseUint(expStr);

        // Calculate the final value: coefficient * 10^exponent
        return coefficient * (10 ** exponent);
    }

    // Helper function to handle coefficients with decimal points
    function _handleDecimalCoefficient(
        string memory coeffStr,
        uint256 decimalPos,
        string memory expStr
    )
        internal
        pure
        returns (uint256)
    {
        bytes memory coeffBytes = bytes(coeffStr);

        // Prepare coefficient without decimal point
        bytes memory withoutDecimal = new bytes(coeffBytes.length - 1);
        uint256 decimalCount = coeffBytes.length - decimalPos - 1;

        uint256 idx = 0;
        // Copy characters before decimal
        for (uint256 i = 0; i < decimalPos; i++) {
            withoutDecimal[idx++] = coeffBytes[i];
        }

        // If coefficient starts with decimal (like .5), prepend a zero
        if (decimalPos == 0) {
            withoutDecimal = new bytes(coeffBytes.length);
            withoutDecimal[0] = "0";
            idx = 1;
        }

        // Copy characters after decimal
        for (uint256 i = decimalPos + 1; i < coeffBytes.length; i++) {
            withoutDecimal[idx++] = coeffBytes[i];
        }

        // Parse coefficient and exponent
        uint256 coefficient = vm.parseUint(string(withoutDecimal));
        uint256 exponent = vm.parseUint(expStr);

        // Adjust exponent for decimal places
        if (decimalCount > 0) {
            exponent = exponent > decimalCount ? exponent - decimalCount : 0;
            if (exponent == 0) return coefficient / (10 ** decimalCount);
        }

        // Calculate the final value: coefficient * 10^exponent
        return coefficient * (10 ** exponent);
    }

    function _fetchConfig() internal {
        string memory configJson = getConfig();

        // Break up the loading into separate functions to reduce stack pressure
        _loadProtocolParams(configJson);
        _loadRateModelParams(configJson);
        _loadAssetParams(configJson);
        _loadBorrowPoolParams(configJson);
        _loadSuperPoolParams(configJson);
        _loadLtvSettings(configJson);

        // Print only key config values for verification
        console2.log("Configuration loaded:");
        console2.log("minLtv:", _protocolParams.minLtv);
        console2.log("maxLtv:", _protocolParams.maxLtv);
        console2.log("borrowAssetPoolCap:", _borrowPoolParams.borrowAssetPoolCap);
        console2.log("collateralLtv:", _ltvSettings.collateralLtv);
    }

    function _loadProtocolParams(string memory configJson) internal {
        // Load data in batches to reduce stack usage
        _loadProtocolOwnerInfo(configJson);
        _loadProtocolLtvRates(configJson);
        _loadProtocolFeeInfo(configJson);
    }

    // Split protocol params loading to reduce stack depth
    function _loadProtocolOwnerInfo(string memory configJson) internal {
        // Protocol ownership params
        _protocolParams.owner = vm.parseJsonAddress(configJson, "$.DeploymentOrchestrator.protocolParams.owner");
        _protocolParams.proxyAdmin =
            vm.parseJsonAddress(configJson, "$.DeploymentOrchestrator.protocolParams.proxyAdmin");
        _protocolParams.feeRecipient =
            vm.parseJsonAddress(configJson, "$.DeploymentOrchestrator.protocolParams.feeRecipient");
    }

    // Handle LTV and rates separately
    function _loadProtocolLtvRates(string memory configJson) internal {
        // LTV params
        string memory minLtvStr = vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.minLtv");
        _protocolParams.minLtv = _parseScientificNotation(minLtvStr);

        string memory maxLtvStr = vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.maxLtv");
        _protocolParams.maxLtv = _parseScientificNotation(maxLtvStr);

        // Min amounts
        string memory minDebtStr = vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.minDebt");
        _protocolParams.minDebt = _parseScientificNotation(minDebtStr);

        string memory minBorrowStr = vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.minBorrow");
        _protocolParams.minBorrow = _parseScientificNotation(minBorrowStr);
    }

    // Handle fee information separately
    function _loadProtocolFeeInfo(string memory configJson) internal {
        // Liquidation related parameters
        string memory liquidationFeeStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.liquidationFee");
        _protocolParams.liquidationFee = _parseScientificNotation(liquidationFeeStr);

        string memory liquidationDiscountStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.liquidationDiscount");
        _protocolParams.liquidationDiscount = _parseScientificNotation(liquidationDiscountStr);

        string memory badDebtLiquidationDiscountStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.badDebtLiquidationDiscount");
        _protocolParams.badDebtLiquidationDiscount = _parseScientificNotation(badDebtLiquidationDiscountStr);

        // Fee parameters
        string memory defaultInterestFeeStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.defaultInterestFee");
        _protocolParams.defaultInterestFee = _parseScientificNotation(defaultInterestFeeStr);

        string memory defaultOriginationFeeStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.protocolParams.defaultOriginationFee");
        _protocolParams.defaultOriginationFee = _parseScientificNotation(defaultOriginationFeeStr);
    }

    function _loadRateModelParams(string memory configJson) internal {
        // KinkedRateModel parameters
        string memory minRateStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.kinkedRateModelParams.minRate");
        _rateModelParams.minRate = _parseScientificNotation(minRateStr);

        string memory slope1Str =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.kinkedRateModelParams.slope1");
        _rateModelParams.slope1 = _parseScientificNotation(slope1Str);

        string memory slope2Str =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.kinkedRateModelParams.slope2");
        _rateModelParams.slope2 = _parseScientificNotation(slope2Str);

        string memory optimalUtilStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.kinkedRateModelParams.optimalUtil");
        _rateModelParams.optimalUtil = _parseScientificNotation(optimalUtilStr);
    }

    function _loadAssetParams(string memory configJson) internal {
        // Assets
        _assetParams.borrowAsset = vm.parseJsonAddress(configJson, "$.DeploymentOrchestrator.assetParams.borrowAsset");
        _assetParams.borrowAssetOracle =
            vm.parseJsonAddress(configJson, "$.DeploymentOrchestrator.assetParams.borrowAssetOracle");
        _assetParams.collateralAsset =
            vm.parseJsonAddress(configJson, "$.DeploymentOrchestrator.assetParams.collateralAsset");
        _assetParams.collateralAssetOracle =
            vm.parseJsonAddress(configJson, "$.DeploymentOrchestrator.assetParams.collateralAssetOracle");
    }

    function _loadBorrowPoolParams(string memory configJson) internal {
        // Borrow asset pool parameters
        string memory borrowAssetPoolCapStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.borrowPoolParams.borrowAssetPoolCap");
        _borrowPoolParams.borrowAssetPoolCap = _parseScientificNotation(borrowAssetPoolCapStr);

        string memory borrowAssetBorrowCapStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.borrowPoolParams.borrowAssetBorrowCap");
        _borrowPoolParams.borrowAssetBorrowCap = _parseScientificNotation(borrowAssetBorrowCapStr);

        string memory borrowAssetInitialDepositStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.borrowPoolParams.borrowAssetInitialDeposit");
        _borrowPoolParams.borrowAssetInitialDeposit = _parseScientificNotation(borrowAssetInitialDepositStr);
    }

    function _loadSuperPoolParams(string memory configJson) internal {
        // SuperPool parameters
        string memory superPoolCapStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.superPoolParams.superPoolCap");
        _superPoolParams.superPoolCap = _parseScientificNotation(superPoolCapStr);

        string memory superPoolFeeStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.superPoolParams.superPoolFee");
        _superPoolParams.superPoolFee = _parseScientificNotation(superPoolFeeStr);

        string memory superPoolInitialDepositStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.superPoolParams.superPoolInitialDeposit");
        _superPoolParams.superPoolInitialDeposit = _parseScientificNotation(superPoolInitialDepositStr);

        _superPoolParams.superPoolName =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.superPoolParams.superPoolName");
        _superPoolParams.superPoolSymbol =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.superPoolParams.superPoolSymbol");
    }

    function _loadLtvSettings(string memory configJson) internal {
        // LTV settings
        string memory collateralLtvStr =
            vm.parseJsonString(configJson, "$.DeploymentOrchestrator.ltvSettings.collateralLtv");
        _ltvSettings.collateralLtv = _parseScientificNotation(collateralLtvStr);
    }

    function _deployProtocolInternal() internal {
        console2.log("1. Deploying core protocol...");

        // Deploy each component in separate functions to reduce stack usage
        _deployRegistry();
        _deployRiskEngine();
        _deployRiskModule();
        _deployPoolComponents();
        _deployPositionComponents();
        _deployLensContracts();
        _setupRegistry();
        _updateRelationships();

        console2.log("Core protocol deployed");
        console2.log("Registry:", registry);
        console2.log("Pool:", pool);
        console2.log("RiskEngine:", riskEngine);
    }

    // Deploy Registry
    function _deployRegistry() internal {
        registry = address(new Registry());
        console2.log("Registry deployed:", registry);
    }

    // Deploy RiskEngine
    function _deployRiskEngine() internal {
        RiskEngine riskEngineImpl = new RiskEngine(registry, _protocolParams.minLtv, _protocolParams.maxLtv);
        riskEngine = address(riskEngineImpl);
        console2.log("RiskEngine deployed:", riskEngine);
    }

    // Deploy RiskModule
    function _deployRiskModule() internal {
        riskModule =
            address(new RiskModule(registry, _protocolParams.liquidationDiscount, _protocolParams.liquidationFee));
        console2.log("RiskModule deployed:", riskModule);
    }

    // Deploy Pool components
    function _deployPoolComponents() internal {
        // Deploy Pool implementation
        Pool _poolImpl = new Pool();
        poolImpl = address(_poolImpl);
        console2.log("Pool implementation deployed:", poolImpl);

        // Deploy Pool proxy
        TransparentUpgradeableProxy poolProxy = new TransparentUpgradeableProxy(
            poolImpl,
            _protocolParams.proxyAdmin,
            abi.encodeWithSelector(
                Pool.initialize.selector,
                _protocolParams.owner,
                registry,
                _protocolParams.feeRecipient,
                _protocolParams.minDebt,
                _protocolParams.minBorrow,
                _protocolParams.defaultInterestFee,
                _protocolParams.defaultOriginationFee
            )
        );
        pool = address(poolProxy);
        console2.log("Pool proxy deployed:", pool);

        // Deploy SuperPoolFactory
        superPoolFactory = address(new SuperPoolFactory(pool));
        console2.log("SuperPoolFactory deployed:", superPoolFactory);
    }

    // Deploy Position components
    function _deployPositionComponents() internal {
        // Deploy PositionManager implementation
        PositionManager _positionManagerImpl = new PositionManager();
        positionManagerImpl = address(_positionManagerImpl);
        console2.log("PositionManager implementation deployed:", positionManagerImpl);

        // Deploy PositionManager proxy
        TransparentUpgradeableProxy positionManagerProxy = new TransparentUpgradeableProxy(
            positionManagerImpl,
            _protocolParams.proxyAdmin,
            abi.encodeWithSelector(PositionManager.initialize.selector, _protocolParams.owner, registry)
        );
        positionManager = address(positionManagerProxy);
        console2.log("PositionManager proxy deployed:", positionManager);

        // Deploy Position
        Position position = new Position(pool, positionManager, riskEngine);
        address positionAddress = address(position);
        console2.log("Position deployed:", positionAddress);

        // Deploy Position beacon
        positionBeacon = address(new UpgradeableBeacon(positionAddress));
        console2.log("Position beacon deployed:", positionBeacon);
    }

    // Deploy Lens contracts
    function _deployLensContracts() internal {
        superPoolLens = address(new SuperPoolLens(pool, riskEngine));
        console2.log("SuperPoolLens deployed:", superPoolLens);

        portfolioLens = address(new PortfolioLens(pool, riskEngine, positionManager));
        console2.log("PortfolioLens deployed:", portfolioLens);
    }

    // Set up the Registry with all components
    function _setupRegistry() internal {
        Registry(registry).setAddress(
            0xd4927490fbcbcafca716cca8e8c8b7d19cda785679d224b14f15ce2a9a93e148, positionManager
        );
        Registry(registry).setAddress(0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728, pool);
        Registry(registry).setAddress(0x5b6696788621a5d6b5e3b02a69896b9dd824ebf1631584f038a393c29b6d7555, riskEngine);
        Registry(registry).setAddress(
            0x6e7384c78b0e09fb848f35d00a7b14fc1ad10ae9b10117368146c0e09b6f2fa2, positionBeacon
        );
        Registry(registry).setAddress(0x881469d14b8443f6c918bdd0a641e9d7cae2592dc28a4f922a2c4d7ca3d19c77, riskModule);
    }

    // Update relationships between contracts
    function _updateRelationships() internal {
        Pool(pool).updateFromRegistry();
        PositionManager(positionManager).updateFromRegistry();
        RiskEngine(riskEngine).updateFromRegistry();
        RiskModule(riskModule).updateFromRegistry();
    }

    function _deployAndRegisterIRMInternal() internal {
        console2.log("2. Deploying and registering IRM...");

        // Deploy KinkedRateModel
        kinkedRateModel = address(
            new KinkedRateModel(
                _rateModelParams.minRate, _rateModelParams.slope1, _rateModelParams.slope2, _rateModelParams.optimalUtil
            )
        );
        console2.log("KinkedRateModel deployed:", kinkedRateModel);

        // Register KinkedRateModel in Registry
        Registry(registry).setRateModel(kinkedRateModelKey, kinkedRateModel);
        console2.log("KinkedRateModel registered with key:", vm.toString(kinkedRateModelKey));
    }

    function _registerOraclesInternal() internal {
        console2.log("3. Registering oracles...");

        // Set oracles for both assets
        RiskEngine(riskEngine).setOracle(_assetParams.borrowAsset, _assetParams.borrowAssetOracle);
        console2.log("Oracle set for borrowAsset:", _assetParams.borrowAsset, "=>", _assetParams.borrowAssetOracle);

        RiskEngine(riskEngine).setOracle(_assetParams.collateralAsset, _assetParams.collateralAssetOracle);
        console2.log(
            "Oracle set for collateralAsset:", _assetParams.collateralAsset, "=>", _assetParams.collateralAssetOracle
        );
    }

    function _initializePoolInternal() internal {
        console2.log("4. Initializing pool...");

        // Approve tokens based on configuration
        if (_borrowPoolParams.borrowAssetInitialDeposit > 0) {
            IERC20(_assetParams.borrowAsset).approve(pool, _borrowPoolParams.borrowAssetInitialDeposit);
            console2.log("Approved borrow asset for initial deposit:", _borrowPoolParams.borrowAssetInitialDeposit);
        }

        // Initialize pool for the borrow asset
        poolId = Pool(pool).initializePool(
            _protocolParams.owner,
            _assetParams.borrowAsset,
            kinkedRateModelKey,
            _borrowPoolParams.borrowAssetPoolCap,
            _borrowPoolParams.borrowAssetBorrowCap,
            _borrowPoolParams.borrowAssetInitialDeposit
        );

        console2.log("Pool initialized with ID:", poolId);
    }

    function _setLtvInternal() internal {
        console2.log("5. Setting LTV...");

        // Request and accept LTV update for the collateral asset
        RiskEngine(riskEngine).requestLtvUpdate(poolId, _assetParams.collateralAsset, _ltvSettings.collateralLtv);

        // Since this is a first-time LTV setting, we can accept it immediately without timelock
        if (RiskEngine(riskEngine).ltvFor(poolId, _assetParams.collateralAsset) == 0) {
            RiskEngine(riskEngine).acceptLtvUpdate(poolId, _assetParams.collateralAsset);
            console2.log("LTV set for collateralAsset in pool:", poolId, _ltvSettings.collateralLtv);
        }
    }

    function _deploySuperPoolInternal() internal {
        console2.log("6. Deploying SuperPool...");

        // Approve tokens based on configuration
        if (_superPoolParams.superPoolInitialDeposit > 0) {
            IERC20(_assetParams.borrowAsset).approve(superPoolFactory, _superPoolParams.superPoolInitialDeposit);
            console2.log("Approved borrow asset for SuperPool Factory:", _superPoolParams.superPoolInitialDeposit);
        }

        console2.log("Deploying SuperPool with parameters:");
        console2.log("- Owner:", _protocolParams.owner);
        console2.log("- Borrow Asset:", _assetParams.borrowAsset);
        console2.log("- Fee Recipient:", _protocolParams.feeRecipient);
        console2.log("- SuperPool Fee:", _superPoolParams.superPoolFee);
        console2.log("- SuperPool Cap:", _superPoolParams.superPoolCap);
        console2.log("- Initial Deposit:", _superPoolParams.superPoolInitialDeposit);
        console2.log("- Name:", _superPoolParams.superPoolName);
        console2.log("- Symbol:", _superPoolParams.superPoolSymbol);

        deployedSuperPool = SuperPoolFactory(superPoolFactory).deploySuperPool(
            _protocolParams.owner,
            _assetParams.borrowAsset,
            _protocolParams.feeRecipient,
            _superPoolParams.superPoolFee,
            _superPoolParams.superPoolCap,
            _superPoolParams.superPoolInitialDeposit,
            _superPoolParams.superPoolName,
            _superPoolParams.superPoolSymbol
        );

        console2.log("SuperPool deployed:", deployedSuperPool);
    }

    function _setPoolCap() internal {
        console2.log("7. Setting pool cap in SuperPool...");

        // Add pool to SuperPool with cap
        SuperPool(deployedSuperPool).addPool(poolId, _superPoolParams.superPoolCap);
        console2.log("Pool added to SuperPool with cap:", _superPoolParams.superPoolCap);
    }

    function _whitelistAssets() internal {
        console2.log("8. Whitelisting assets in PositionManager...");

        // Whitelist borrow and collateral assets
        PositionManager(positionManager).toggleKnownAsset(_assetParams.borrowAsset);
        console2.log("Whitelisted borrowAsset:", _assetParams.borrowAsset);

        PositionManager(positionManager).toggleKnownAsset(_assetParams.collateralAsset);
        console2.log("Whitelisted collateralAsset:", _assetParams.collateralAsset);
    }

    function _logToConsole() internal view {
        // Core protocol addresses
        console2.log("Core protocol addresses:");
        console2.log("- Registry:", registry);
        console2.log("- Pool:", pool);
        console2.log("- RiskEngine:", riskEngine);
        console2.log("- RiskModule:", riskModule);
        console2.log("- PositionManager:", positionManager);
        console2.log("- SuperPoolFactory:", superPoolFactory);
        console2.log("- PositionBeacon:", positionBeacon);
        console2.log("- SuperPoolLens:", superPoolLens);
        console2.log("- PortfolioLens:", portfolioLens);

        console2.log("IRM:");
        console2.log("- KinkedRateModel:", kinkedRateModel);
        console2.log("- KinkedRateModelKey:", vm.toString(kinkedRateModelKey));

        console2.log("Pool details:");
        console2.log("- PoolId:", poolId);

        console2.log("Asset details:");
        console2.log("- BorrowAsset:", _assetParams.borrowAsset);
        console2.log("- BorrowAssetOracle:", _assetParams.borrowAssetOracle);
        console2.log("- CollateralAsset:", _assetParams.collateralAsset);
        console2.log("- CollateralAssetOracle:", _assetParams.collateralAssetOracle);

        console2.log("SuperPool:");
        console2.log("- DeployedSuperPool:", deployedSuperPool);

        console2.log("Deployment details:");
        console2.log("- ChainId:", block.chainid);
        console2.log("- Timestamp:", vm.getBlockTimestamp());
    }
}
