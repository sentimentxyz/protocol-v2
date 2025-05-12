// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseScript} from "../BaseScript.s.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Position} from "../../src/Position.sol";
import {PositionManager, DebtData, AssetData} from "../../src/PositionManager.sol";
import {Pool} from "../../src/Pool.sol";
import {RiskEngine} from "../../src/RiskEngine.sol";
import {RiskModule} from "../../src/RiskModule.sol";
import {Registry} from "../../src/Registry.sol";

/**
 * @title LiquidatePosition
 * @notice Script to manually liquidate an unhealthy position
 * @dev Run with:
 *   forge script script/liquidations/LiquidatePosition.s.sol:LiquidatePosition --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast -vvvv --sig "run(address)" <POSITION_ADDRESS>
 */
contract LiquidatePosition is BaseScript, Test {
    // Registry keys
    bytes32 public constant SENTIMENT_POOL_KEY =
        0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728;
    bytes32 public constant SENTIMENT_RISK_ENGINE_KEY =
        0x5b6696788621a5d6b5e3b02a69896b9dd824ebf1631584f038a393c29b6d7555;
    bytes32 public constant SENTIMENT_RISK_MODULE_KEY =
        0x7f16b5acb37cda5a0d0e6575e9d65afc0f46db0e4ed63ae5a8eced15aef1dded;
    bytes32 public constant SENTIMENT_POSITION_MANAGER_KEY =
        0x6dd43ab6d3bb2aa7a9f308ce05c7af32c69fde182d0ee8f86cc9fa464a1a764e;

    // Hardcoded liquidation discount (20%)
    uint256 public constant LIQUIDATION_DISCOUNT = 0.2e18;

    // Contract addresses
    address public positionManagerAddr;
    address public poolAddr;
    address public riskEngineAddr;
    address public riskModuleAddr;
    address public registryAddr;

    // Contract instances
    PositionManager private _positionManager;
    Pool private _pool;
    RiskEngine private _riskEngine;
    RiskModule private _riskModule;
    Registry private _registry;

    function setUp() public {
        // Load registry address from environment or use a fallback
        string memory registryAddrStr = vm.envString("REGISTRY_ADDRESS");
        registryAddr = bytes(registryAddrStr).length > 0
            ? vm.parseAddress(registryAddrStr)
            : address(0);

        if (registryAddr == address(0)) {
            console.log(
                "Registry address not set in environment variables. Using hardcoded addresses instead."
            );
            // Load contract addresses from environment or use fallbacks
            string memory positionManagerAddrStr = vm.envString(
                "POSITION_MANAGER_ADDRESS"
            );
            positionManagerAddr = bytes(positionManagerAddrStr).length > 0
                ? vm.parseAddress(positionManagerAddrStr)
                : address(0);

            string memory poolAddrStr = vm.envString("POOL_ADDRESS");
            poolAddr = bytes(poolAddrStr).length > 0
                ? vm.parseAddress(poolAddrStr)
                : address(0);

            string memory riskEngineAddrStr = vm.envString(
                "RISK_ENGINE_ADDRESS"
            );
            riskEngineAddr = bytes(riskEngineAddrStr).length > 0
                ? vm.parseAddress(riskEngineAddrStr)
                : address(0);

            string memory riskModuleAddrStr = vm.envString(
                "RISK_MODULE_ADDRESS"
            );
            riskModuleAddr = bytes(riskModuleAddrStr).length > 0
                ? vm.parseAddress(riskModuleAddrStr)
                : address(0);

            require(
                positionManagerAddr != address(0),
                "PositionManager address not set"
            );
            require(poolAddr != address(0), "Pool address not set");
            require(riskEngineAddr != address(0), "RiskEngine address not set");
            require(riskModuleAddr != address(0), "RiskModule address not set");
        } else {
            console.log("Using Registry at address:", registryAddr);
            _registry = Registry(registryAddr);

            // Get contract addresses from registry
            positionManagerAddr = _registry.addressFor(
                SENTIMENT_POSITION_MANAGER_KEY
            );
            poolAddr = _registry.addressFor(SENTIMENT_POOL_KEY);
            riskEngineAddr = _registry.addressFor(SENTIMENT_RISK_ENGINE_KEY);
            riskModuleAddr = _registry.addressFor(SENTIMENT_RISK_MODULE_KEY);

            console.log("Loaded addresses from registry:");
        }

        // Log the addresses being used
        console.log("PositionManager:", positionManagerAddr);
        console.log("Pool:", poolAddr);
        console.log("RiskEngine:", riskEngineAddr);
        console.log("RiskModule:", riskModuleAddr);

        // Initialize contract instances
        _positionManager = PositionManager(positionManagerAddr);
        _pool = Pool(poolAddr);
        _riskEngine = RiskEngine(riskEngineAddr);
        _riskModule = RiskModule(riskModuleAddr);
    }

    function run(address position) external {
        setUp();
        require(position != address(0), "Position address cannot be zero");

        console.log("===============================================");
        console.log("LIQUIDATION SCRIPT - TARGET POSITION:", position);
        console.log("===============================================");

        // Check if the position actually exists and get the owner
        address positionOwner = _positionManager.ownerOf(position);
        console.log("Position owner:", positionOwner);
        require(
            positionOwner != address(0),
            "Position does not exist or is not registered"
        );

        // Check if the position is actually unhealthy
        uint256 healthFactor = _riskEngine.getPositionHealthFactor(position);
        console.log("Position health factor:", healthFactor);
        require(healthFactor < 1e18, "Position is healthy, cannot liquidate");

        // Start broadcasting transactions
        vm.startBroadcast();

        // Get position's debt pools and assets
        uint256[] memory debtPools = Position(payable(position)).getDebtPools();
        address[] memory positionAssets = Position(payable(position))
            .getPositionAssets();

        require(debtPools.length > 0, "Position has no debt");
        require(positionAssets.length > 0, "Position has no assets");

        console.log("\n===============================================");
        console.log("POSITION DETAILS");
        console.log("===============================================");
        console.log("Position has debt pools:", debtPools.length);
        console.log("Position has assets:", positionAssets.length);

        // Get total debt and asset values
        (uint256 totalAssetValue, uint256 totalDebtValue, ) = _riskModule
            .getRiskData(position);
        console.log("Total asset value (ETH):", totalAssetValue);
        console.log("Total debt value (ETH):", totalDebtValue);

        // Show details about each debt pool
        console.log("\n===============================================");
        console.log("DEBT POOL DETAILS");
        console.log("===============================================");

        // Create debt data for liquidation (repay max amount for all pools)
        DebtData[] memory debtData = new DebtData[](debtPools.length);
        uint256 totalRepayValue = 0;

        for (uint256 i = 0; i < debtPools.length; i++) {
            uint256 poolId = debtPools[i];
            address poolAsset = _pool.getPoolAssetFor(poolId);
            uint256 amountToRepay = _pool.getBorrowsOf(poolId, position);

            console.log("Pool ID:", poolId);
            console.log("Asset:", poolAsset);
            console.log("Borrow amount:", amountToRepay);

            // Create debt data entry
            debtData[i] = DebtData({
                poolId: poolId,
                amt: type(uint256).max // Repay maximum amount
            });

            // Approve the position manager to take tokens from liquidator for repayment
            uint256 liquidatorBalance = IERC20(poolAsset).balanceOf(msg.sender);
            console.log("Liquidator balance:", liquidatorBalance);

            if (liquidatorBalance < amountToRepay) {
                console.log(
                    "WARNING: Liquidator doesn't have enough tokens to repay debt"
                );
                console.log("Required:", amountToRepay);
                console.log("Available:", liquidatorBalance);
            }

            IERC20(poolAsset).approve(positionManagerAddr, amountToRepay);
            console.log(
                "Approved PositionManager to use tokens:",
                amountToRepay
            );

            // Track total repay value for calculating seize value
            uint256 repayValueInEth = _riskEngine.getValueInEth(
                poolAsset,
                amountToRepay
            );
            totalRepayValue += repayValueInEth;
            console.log("Value in ETH:", repayValueInEth);
        }

        console.log("Total repay value in ETH:", totalRepayValue);

        // Show details about each asset
        console.log("\n===============================================");
        console.log("ASSET DETAILS");
        console.log("===============================================");

        // Calculate maximum seize value based on liquidation discount (hardcoded as 0.2e18 = 20%)
        uint256 maxSeizeValue = (totalRepayValue * 1e18) /
            (1e18 - LIQUIDATION_DISCOUNT);
        console.log("Max seize value based on 20% discount:", maxSeizeValue);

        // Get asset data with proper scaling to respect max seize value
        (
            AssetData[] memory assetData,
            uint256 totalSeizeValue
        ) = _calculateAssetData(position, positionAssets, maxSeizeValue);

        console.log("\n===============================================");
        console.log("LIQUIDATION SUMMARY");
        console.log("===============================================");
        console.log("Total repay value:", totalRepayValue);
        console.log("Liquidation discount (%):", LIQUIDATION_DISCOUNT / 1e16);
        console.log("Max seize value:", maxSeizeValue);
        console.log("Total asset value to seize:", totalSeizeValue);

        // Execute liquidation
        console.log("\n===============================================");
        console.log("EXECUTING LIQUIDATION");
        console.log("===============================================");

        try _positionManager.liquidate(position, debtData, assetData) {
            console.log("Liquidation successful!");

            // Log results - show what was seized
            console.log("\n===============================================");
            console.log("LIQUIDATION RESULTS");
            console.log("===============================================");

            for (uint256 i = 0; i < positionAssets.length; i++) {
                address asset = positionAssets[i];
                uint256 balanceAfter = IERC20(asset).balanceOf(msg.sender);
                console.log("Asset:", asset);
                console.log("Liquidator balance after:", balanceAfter);
            }

            // Check final position health
            uint256 newHealthFactor = _riskEngine.getPositionHealthFactor(
                position
            );
            console.log("New position health factor:", newHealthFactor);
        } catch Error(string memory reason) {
            console.log("Liquidation failed with reason:", reason);
        } catch (bytes memory) {
            console.log("Liquidation failed with unknown error");
        }

        vm.stopBroadcast();
    }

    // Helper function to calculate asset data with proper scaling based on max seize value
    function _calculateAssetData(
        address position,
        address[] memory positionAssets,
        uint256 maxSeizeValue
    )
        internal
        view
        returns (AssetData[] memory assetData, uint256 totalSeizeValue)
    {
        assetData = new AssetData[](positionAssets.length);

        // First, calculate the total value of all assets
        uint256 totalAssetValue = 0;
        uint256[] memory assetBalances = new uint256[](positionAssets.length);
        uint256[] memory assetValues = new uint256[](positionAssets.length);

        for (uint256 i = 0; i < positionAssets.length; i++) {
            address asset = positionAssets[i];
            uint256 assetBalance = IERC20(asset).balanceOf(position);
            uint256 assetValueInEth = _riskEngine.getValueInEth(
                asset,
                assetBalance
            );

            assetBalances[i] = assetBalance;
            assetValues[i] = assetValueInEth;
            totalAssetValue += assetValueInEth;

            console.log("Asset:", asset);
            console.log("Balance:", assetBalance);
            console.log("Value in ETH:", assetValueInEth);
        }

        // If total value exceeds max seize value, scale down proportionally
        if (totalAssetValue > maxSeizeValue) {
            console.log(
                "Total asset value exceeds max seize value, scaling down proportionally"
            );

            for (uint256 i = 0; i < positionAssets.length; i++) {
                // Calculate scaled amount based on proportion of total value
                uint256 scaledAssetAmt;
                if (assetBalances[i] > 0) {
                    scaledAssetAmt =
                        (assetBalances[i] * maxSeizeValue) /
                        totalAssetValue;
                } else {
                    scaledAssetAmt = 0;
                }

                assetData[i] = AssetData({
                    asset: positionAssets[i],
                    amt: scaledAssetAmt
                });

                uint256 scaledValue = _riskEngine.getValueInEth(
                    positionAssets[i],
                    scaledAssetAmt
                );
                totalSeizeValue += scaledValue;

                console.log("Scaled amount to seize:", scaledAssetAmt);
                console.log("Scaled value in ETH:", scaledValue);
            }
        } else {
            // If total value is less than max seize value, take everything
            for (uint256 i = 0; i < positionAssets.length; i++) {
                assetData[i] = AssetData({
                    asset: positionAssets[i],
                    amt: assetBalances[i]
                });

                totalSeizeValue += assetValues[i];
            }
        }

        return (assetData, totalSeizeValue);
    }

    // Helper function for bad debt liquidation
    function runBadDebt(address position) external {
        setUp();
        require(position != address(0), "Position address cannot be zero");

        console.log("===============================================");
        console.log("BAD DEBT LIQUIDATION SCRIPT - TARGET POSITION:", position);
        console.log("===============================================");

        // Get total debt and asset values
        (uint256 totalAssetValue, uint256 totalDebtValue, ) = _riskModule
            .getRiskData(position);
        console.log("Total asset value (ETH):", totalAssetValue);
        console.log("Total debt value (ETH):", totalDebtValue);

        // Check if position has bad debt
        require(
            totalAssetValue < totalDebtValue,
            "Position does not have bad debt"
        );

        // Start broadcasting transactions
        vm.startBroadcast();

        // Get position's debt pools
        uint256[] memory debtPools = Position(payable(position)).getDebtPools();
        require(debtPools.length > 0, "Position has no debt");

        // Create debt data for liquidation
        DebtData[] memory debtData = new DebtData[](debtPools.length);

        for (uint256 i = 0; i < debtPools.length; i++) {
            uint256 poolId = debtPools[i];
            address poolAsset = _pool.getPoolAssetFor(poolId);
            uint256 amountToRepay = _pool.getBorrowsOf(poolId, position);

            // Create debt data entry
            debtData[i] = DebtData({
                poolId: poolId,
                amt: type(uint256).max // Repay maximum amount
            });

            // Approve the position manager to take tokens from liquidator
            IERC20(poolAsset).approve(positionManagerAddr, amountToRepay);
        }

        // Execute bad debt liquidation
        console.log("Executing bad debt liquidation...");

        try _positionManager.liquidateBadDebt(position, debtData) {
            console.log("Bad debt liquidation successful!");

            // Get position's assets
            address[] memory positionAssets = Position(payable(position))
                .getPositionAssets();

            // Log results - show what was seized
            for (uint256 i = 0; i < positionAssets.length; i++) {
                address asset = positionAssets[i];
                uint256 balanceAfter = IERC20(asset).balanceOf(msg.sender);
                console.log("Asset:", asset);
                console.log("Liquidator balance:", balanceAfter);
            }
        } catch Error(string memory reason) {
            console.log("Bad debt liquidation failed with reason:", reason);
        } catch (bytes memory) {
            console.log("Liquidation failed with unknown error");
        }

        vm.stopBroadcast();
    }
}
