// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Pool } from "../../src/Pool.sol";
import { Position } from "../../src/Position.sol";
import { AssetData, DebtData, PositionManager } from "../../src/PositionManager.sol";
import { Registry } from "../../src/Registry.sol";
import { RiskEngine } from "../../src/RiskEngine.sol";
import { RiskModule } from "../../src/RiskModule.sol";
import { BaseScript } from "../BaseScript.s.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @title LiquidatePosition
 * @notice Script to manually liquidate an unhealthy position
 * @dev Run with:
 *   forge script script/liquidations/LiquidatePosition.s.sol:LiquidatePosition --rpc-url <RPC_URL> --private-key
 * <PRIVATE_KEY> --broadcast -vvvv --sig "run(address)" <POSITION_ADDRESS>
 *
 * Important: If the script is being run from an EOA that has the tokens needed for repayment, you must specify the
 * --sender flag:
 *   forge script script/liquidations/LiquidatePosition.s.sol:LiquidatePosition --rpc-url <RPC_URL> --private-key
 * <PRIVATE_KEY> --broadcast -vvvv --sig "run(address)" <POSITION_ADDRESS> --sender <YOUR_WALLET_ADDRESS>
 */
contract LiquidatePosition is BaseScript {
    using SafeERC20 for IERC20;

    // Registry keys
    bytes32 public constant SENTIMENT_POOL_KEY = 0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728;
    bytes32 public constant SENTIMENT_RISK_ENGINE_KEY =
        0x5b6696788621a5d6b5e3b02a69896b9dd824ebf1631584f038a393c29b6d7555;
    bytes32 public constant SENTIMENT_RISK_MODULE_KEY =
        0x881469d14b8443f6c918bdd0a641e9d7cae2592dc28a4f922a2c4d7ca3d19c77;
    bytes32 public constant SENTIMENT_POSITION_MANAGER_KEY =
        0xd4927490fbcbcafca716cca8e8c8b7d19cda785679d224b14f15ce2a9a93e148;

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

    // Empty run function as required by Forge
    function run() public { }

    function _setUp() internal {
        registryAddr = 0x121430beCc13238ef81e40A968d019Fc8dFB2605;

        if (registryAddr == address(0)) {
            console2.log("Registry address not set in environment variables. Using hardcoded addresses instead.");
            // Load contract addresses from environment or use fallbacks
            string memory positionManagerAddrStr = vm.envString("POSITION_MANAGER_ADDRESS");
            positionManagerAddr =
                bytes(positionManagerAddrStr).length > 0 ? vm.parseAddress(positionManagerAddrStr) : address(0);

            string memory poolAddrStr = vm.envString("POOL_ADDRESS");
            poolAddr = bytes(poolAddrStr).length > 0 ? vm.parseAddress(poolAddrStr) : address(0);

            string memory riskEngineAddrStr = vm.envString("RISK_ENGINE_ADDRESS");
            riskEngineAddr = bytes(riskEngineAddrStr).length > 0 ? vm.parseAddress(riskEngineAddrStr) : address(0);

            string memory riskModuleAddrStr = vm.envString("RISK_MODULE_ADDRESS");
            riskModuleAddr = bytes(riskModuleAddrStr).length > 0 ? vm.parseAddress(riskModuleAddrStr) : address(0);

            require(positionManagerAddr != address(0), "PositionManager address not set");
            require(poolAddr != address(0), "Pool address not set");
            require(riskEngineAddr != address(0), "RiskEngine address not set");
            require(riskModuleAddr != address(0), "RiskModule address not set");
        } else {
            console2.log("Using Registry at address:", registryAddr);
            _registry = Registry(registryAddr);

            // Get contract addresses from registry
            positionManagerAddr = _registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY);
            poolAddr = _registry.addressFor(SENTIMENT_POOL_KEY);
            riskEngineAddr = _registry.addressFor(SENTIMENT_RISK_ENGINE_KEY);
            riskModuleAddr = _registry.addressFor(SENTIMENT_RISK_MODULE_KEY);
        }

        // Initialize contract instances
        _positionManager = PositionManager(positionManagerAddr);
        _pool = Pool(poolAddr);
        _riskEngine = RiskEngine(riskEngineAddr);
        _riskModule = RiskModule(riskModuleAddr);
    }

    function run(address position) public {
        _setUp();
        require(position != address(0), "Position address cannot be zero");

        console2.log("\n===============================================");
        console2.log("LIQUIDATION SCRIPT - TARGET POSITION:", position);
        console2.log("===============================================");
        console2.log("Position owner:", _positionManager.ownerOf(position));
        console2.log("Transaction sender (from private key):", msg.sender);

        // Get position's debt pools to approve all debt tokens with max approval
        Position pos = Position(payable(position));
        uint256[] memory debtPools = pos.getDebtPools();

        // Single broadcast for the entire operation
        vm.startBroadcast();

        // For each debt token
        for (uint256 i = 0; i < debtPools.length; i++) {
            address poolAsset = _pool.getPoolAssetFor(debtPools[i]);
            uint256 debtAmount = _pool.getBorrowsOf(debtPools[i], position);

            console2.log("\nHandling debt token:", poolAsset);
            console2.log("Debt amount:", debtAmount);

            // Check balance
            uint256 tokenBalance = IERC20(poolAsset).balanceOf(msg.sender);
            console2.log("Your balance:", tokenBalance);

            if (tokenBalance < debtAmount) {
                console2.log("WARNING: You don't have enough tokens to repay the debt!");
                vm.stopBroadcast();
                return;
            }

            IERC20(poolAsset).forceApprove(positionManagerAddr, type(uint256).max);
        }

        console2.log("\nStarting liquidation...");
        _liquidatePosition(position);

        vm.stopBroadcast();
    }

    function runBadDebt(address position) public {
        _setUp();
        require(position != address(0), "Position address cannot be zero");

        // Print debt tokens needed for liquidation
        Position pos = Position(payable(position));
        uint256[] memory debtPools = pos.getDebtPools();
        console2.log("\nDebt tokens needed for bad debt liquidation:");
        for (uint256 i = 0; i < debtPools.length; i++) {
            address poolAsset = _pool.getPoolAssetFor(debtPools[i]);
            uint256 amountOwed = _pool.getBorrowsOf(debtPools[i], position);
            console2.log("Token:", poolAsset);
            console2.log("Amount:", amountOwed);
        }

        // Start broadcast with private key
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        _liquidateBadDebt(position);
        vm.stopBroadcast();
    }

    function _liquidatePosition(address position) internal {
        console2.log("===============================================");
        console2.log("LIQUIDATION SCRIPT - TARGET POSITION:", position);
        console2.log("===============================================");
        console2.log("Script caller (who approves tokens):", msg.sender);
        console2.log("Position Manager address:", positionManagerAddr);
        console2.log("Pool address:", poolAddr);

        // Check if the position actually exists and get the owner
        address positionOwner = _positionManager.ownerOf(position);
        console2.log("Position owner:", positionOwner);
        require(positionOwner != address(0), "Position does not exist or is not registered");

        // Check if the position is actually unhealthy
        uint256 healthFactor = _riskEngine.getPositionHealthFactor(position);
        console2.log("Position health factor:", healthFactor);
        require(healthFactor < 1e18, "Position is healthy, cannot liquidate");

        // Get position's debt pools and assets
        uint256[] memory debtPools = Position(payable(position)).getDebtPools();
        address[] memory positionAssets = Position(payable(position)).getPositionAssets();

        require(debtPools.length > 0, "Position has no debt");
        require(positionAssets.length > 0, "Position has no assets");

        console2.log("\n===============================================");
        console2.log("POSITION DETAILS");
        console2.log("===============================================");
        console2.log("Position has debt pools:", debtPools.length);
        console2.log("Position has assets:", positionAssets.length);

        // Get total debt and asset values
        (uint256 totalAssetValue, uint256 totalDebtValue,) = _riskModule.getRiskData(position);
        console2.log("Total asset value (ETH):", totalAssetValue);
        console2.log("Total debt value (ETH):", totalDebtValue);

        // Show details about each debt pool
        console2.log("\n===============================================");
        console2.log("DEBT POOL DETAILS");
        console2.log("===============================================");

        // Create debt data for liquidation (repay max amount for all pools)
        DebtData[] memory debtData = new DebtData[](debtPools.length);
        uint256 totalRepayValue = 0;

        for (uint256 i = 0; i < debtPools.length; i++) {
            uint256 poolId = debtPools[i];
            address poolAsset = _pool.getPoolAssetFor(poolId);
            uint256 amountToRepay = _pool.getBorrowsOf(poolId, position);

            console2.log("Pool ID:", poolId);
            console2.log("Asset:", poolAsset);
            console2.log("Borrow amount:", amountToRepay);

            // Create debt data entry
            debtData[i] = DebtData({
                poolId: poolId,
                amt: type(uint256).max // Repay maximum amount
             });

            // Check liquidator balance
            uint256 liquidatorBalance = IERC20(poolAsset).balanceOf(msg.sender);
            console2.log("Liquidator balance:", liquidatorBalance);
            console2.log("Liquidator address:", msg.sender);
            console2.log("Current allowance to Pool:", IERC20(poolAsset).allowance(msg.sender, poolAddr));

            if (liquidatorBalance < amountToRepay) {
                console2.log("WARNING: Liquidator doesn't have enough tokens to repay debt");
                console2.log("Required:", amountToRepay);
                console2.log("Available:", liquidatorBalance);
            }

            // Track total repay value for calculating seize value
            uint256 repayValueInEth = _riskEngine.getValueInEth(poolAsset, amountToRepay);
            totalRepayValue += repayValueInEth;
            console2.log("Value in ETH:", repayValueInEth);
        }

        console2.log("Total repay value in ETH:", totalRepayValue);

        // Show details about each asset
        console2.log("\n===============================================");
        console2.log("ASSET DETAILS");
        console2.log("===============================================");

        // Calculate maximum seize value based on liquidation discount (hardcoded as 0.2e18 = 20%)
        uint256 maxSeizeValue = (totalRepayValue * 1e18) / (1e18 - LIQUIDATION_DISCOUNT);
        console2.log("Max seize value based on 20% discount:", maxSeizeValue);

        // Get asset data with proper scaling to respect max seize value
        (AssetData[] memory assetData, uint256 totalSeizeValue) =
            _calculateAssetData(position, positionAssets, maxSeizeValue);

        console2.log("\n===============================================");
        console2.log("LIQUIDATION SUMMARY");
        console2.log("===============================================");
        console2.log("Total repay value:", totalRepayValue);
        console2.log("Liquidation discount (%):", LIQUIDATION_DISCOUNT / 1e16);
        console2.log("Max seize value:", maxSeizeValue);
        console2.log("Total asset value to seize:", totalSeizeValue);

        // Execute liquidation
        console2.log("\n===============================================");
        console2.log("EXECUTING LIQUIDATION");
        console2.log("===============================================");
        console2.log("Liquidator:", msg.sender);
        console2.log("Position:", position);
        console2.log("Position manager:", positionManagerAddr);

        try _positionManager.liquidate(position, debtData, assetData) {
            console2.log("Liquidation successful!");

            // Log results - show what was seized
            console2.log("\n===============================================");
            console2.log("LIQUIDATION RESULTS");
            console2.log("===============================================");

            for (uint256 i = 0; i < positionAssets.length; i++) {
                address asset = positionAssets[i];
                uint256 balanceAfter = IERC20(asset).balanceOf(msg.sender);
                console2.log("Asset:", asset);
                console2.log("Liquidator balance after:", balanceAfter);
            }

            // Check final position health
            uint256 newHealthFactor = _riskEngine.getPositionHealthFactor(position);
            console2.log("New position health factor:", newHealthFactor);
        } catch Error(string memory reason) {
            console2.log("Liquidation failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console2.log("Liquidation failed with low-level error");
            console2.logBytes(lowLevelData);
        }
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
            uint256 assetValueInEth = _riskEngine.getValueInEth(asset, assetBalance);

            assetBalances[i] = assetBalance;
            assetValues[i] = assetValueInEth;
            totalAssetValue += assetValueInEth;

            console2.log("Asset:", asset);
            console2.log("Balance:", assetBalance);
            console2.log("Value in ETH:", assetValueInEth);
        }

        // Owner fee buffer - assume a small percentage of assets go to the position owner
        // This prevents the liquidation from trying to seize more than available after fees
        uint256 ownerFeeBuffer = 0.02e18; // 2% buffer for owner fees
        uint256 adjustedMaxSeizeValue = (maxSeizeValue * (1e18 - ownerFeeBuffer)) / 1e18;
        console2.log("Adjusted max seize value with owner fee buffer:", adjustedMaxSeizeValue);

        // If total value exceeds max seize value, scale down proportionally
        if (totalAssetValue > adjustedMaxSeizeValue) {
            console2.log("Total asset value exceeds max seize value, scaling down proportionally");

            for (uint256 i = 0; i < positionAssets.length; i++) {
                // Calculate scaled amount based on proportion of total value
                uint256 scaledAssetAmt;
                if (assetBalances[i] > 0) scaledAssetAmt = (assetBalances[i] * adjustedMaxSeizeValue) / totalAssetValue;
                else scaledAssetAmt = 0;

                assetData[i] = AssetData({ asset: positionAssets[i], amt: scaledAssetAmt });

                uint256 scaledValue = _riskEngine.getValueInEth(positionAssets[i], scaledAssetAmt);
                totalSeizeValue += scaledValue;

                console2.log("Scaled amount to seize:", scaledAssetAmt);
                console2.log("Scaled value in ETH:", scaledValue);
            }
        } else {
            // If total value is less than max seize value, take everything
            for (uint256 i = 0; i < positionAssets.length; i++) {
                assetData[i] = AssetData({ asset: positionAssets[i], amt: assetBalances[i] });

                totalSeizeValue += assetValues[i];
            }
        }

        return (assetData, totalSeizeValue);
    }

    function _liquidateBadDebt(address position) internal {
        console2.log("===============================================");
        console2.log("BAD DEBT LIQUIDATION SCRIPT - TARGET POSITION:", position);
        console2.log("===============================================");

        // Get total debt and asset values
        (uint256 totalAssetValue, uint256 totalDebtValue,) = _riskModule.getRiskData(position);
        console2.log("Total asset value (ETH):", totalAssetValue);
        console2.log("Total debt value (ETH):", totalDebtValue);

        // Check if position has bad debt
        require(totalAssetValue < totalDebtValue, "Position does not have bad debt");

        // Get position's debt pools
        uint256[] memory debtPools = Position(payable(position)).getDebtPools();
        require(debtPools.length > 0, "Position has no debt");

        // Create debt data for liquidation
        DebtData[] memory debtData = new DebtData[](debtPools.length);

        for (uint256 i = 0; i < debtPools.length; i++) {
            uint256 poolId = debtPools[i];
            address poolAsset = _pool.getPoolAssetFor(poolId);

            // Log pool asset for debugging
            console2.log("Pool asset:", poolAsset);

            // Create debt data entry
            debtData[i] = DebtData({
                poolId: poolId,
                amt: type(uint256).max // Repay maximum amount
             });
        }

        // Execute bad debt liquidation
        console2.log("Executing bad debt liquidation...");

        try _positionManager.liquidateBadDebt(position, debtData) {
            console2.log("Bad debt liquidation successful!");

            // Get position's assets
            address[] memory positionAssets = Position(payable(position)).getPositionAssets();

            // Log results - show what was seized
            for (uint256 i = 0; i < positionAssets.length; i++) {
                address asset = positionAssets[i];
                uint256 balanceAfter = IERC20(asset).balanceOf(msg.sender);
                console2.log("Asset:", asset);
                console2.log("Liquidator balance:", balanceAfter);
            }
        } catch Error(string memory reason) {
            console2.log("Bad debt liquidation failed with reason:", reason);
        } catch (bytes memory) {
            console2.log("Liquidation failed with unknown error");
        }
    }
}
