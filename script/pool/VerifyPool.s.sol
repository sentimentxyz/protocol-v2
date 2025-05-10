// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseScript} from "../BaseScript.s.sol";
import {StringUtils} from "../StringUtils.s.sol";
import {console2} from "forge-std/console2.sol";

import {Pool} from "src/Pool.sol";
import {Registry} from "src/Registry.sol";
import {RiskEngine} from "src/RiskEngine.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

// Define the IPool interface with individual getter functions
interface IPool {
    function ownerOf(uint256 poolId) external view returns (address);
    function getLiquidityOf(uint256 poolId) external view returns (uint256);
    function getTotalAssets(uint256 poolId) external view returns (uint256);
    function getTotalBorrows(uint256 poolId) external view returns (uint256);
    function getPoolAssetFor(uint256 poolId) external view returns (address);
    function getRateModelFor(uint256 poolId) external view returns (address);
    function getPoolCapFor(uint256 poolId) external view returns (uint256);
    function getBorrowCapFor(uint256 poolId) external view returns (uint256);
}

contract VerifyPool is BaseScript, StringUtils {
    address public pool;
    address public asset;
    uint256 public poolId;

    // For verification checking
    address public registry;
    address public riskEngine;

    function run() public {
        getParams();

        // Access the Pool contract through the IPool interface
        IPool ipool = IPool(pool);

        // Get pool data using individual getters
        address owner = ipool.ownerOf(poolId);
        address poolAsset = ipool.getPoolAssetFor(poolId);
        address rateModel = ipool.getRateModelFor(poolId);
        uint256 depositCap = ipool.getPoolCapFor(poolId);
        uint256 borrowCap = ipool.getBorrowCapFor(poolId);

        // Get additional data
        uint256 liquidAssets = ipool.getLiquidityOf(poolId);
        uint256 totalAssetsWithInterest = ipool.getTotalAssets(poolId);
        uint256 totalBorrowsWithInterest = ipool.getTotalBorrows(poolId);

        // Get Oracle info via RiskEngine
        address assetOracle = RiskEngine(riskEngine).oracleFor(poolAsset);

        // Log all the verification info
        console2.log("=== Pool Verification ===");
        console2.log("Pool Contract: ", pool);
        console2.log("Pool ID: ", poolId);
        console2.log("Owner: ", owner);
        console2.log("Asset: ", poolAsset);

        // Try to get token symbol and decimals but handle potential errors
        try IERC20(poolAsset).symbol() returns (string memory symbol) {
            console2.log("Asset Symbol: ", symbol);
        } catch {
            console2.log("Asset Symbol: <not available>");
        }

        try IERC20(poolAsset).decimals() returns (uint8 decimals) {
            console2.log("Asset Decimals: ", decimals);
        } catch {
            console2.log("Asset Decimals: <not available>");
        }

        console2.log("Rate Model Address: ", rateModel);
        console2.log("Deposit Cap: ", depositCap);
        console2.log("Borrow Cap: ", borrowCap);
        console2.log("Total Assets (with interest): ", totalAssetsWithInterest);
        console2.log(
            "Total Borrows (with interest): ",
            totalBorrowsWithInterest
        );
        console2.log("Liquid Assets: ", liquidAssets);
        console2.log("Asset Oracle: ", assetOracle);

        if (address(assetOracle) == address(0)) {
            console2.log("WARNING: No oracle registered for asset!");
        } else {
            console2.log("Oracle is properly registered");
        }

        // Check if initial deposit was successful
        if (totalAssetsWithInterest == 0) {
            console2.log("WARNING: No deposits in the pool!");
        } else {
            console2.log("Initial deposit confirmed");
        }

        // Configuration success summary
        bool configSuccess = (poolAsset == asset &&
            depositCap > 0 &&
            borrowCap > 0 &&
            rateModel != address(0) &&
            totalAssetsWithInterest > 0);

        console2.log("=== Verification Result ===");
        console2.log(
            "Pool initialized correctly: ",
            configSuccess ? "YES" : "NO"
        );
    }

    function getParams() internal {
        string memory config = getConfig();

        // Get basic params from InitializePool section
        pool = vm.parseJsonAddress(config, "$.InitializePool.pool");
        asset = vm.parseJsonAddress(config, "$.InitializePool.asset");

        // Get addresses of core contracts
        registry = vm.parseJsonAddress(config, "$.VerifyPool.registry");
        riskEngine = vm.parseJsonAddress(config, "$.VerifyPool.riskEngine");

        // If we already know the poolId, read it, otherwise we need to compute it
        string memory poolIdPath = "$.VerifyPool.poolId";

        try vm.parseJsonString(config, poolIdPath) returns (
            string memory poolIdStr
        ) {
            if (bytes(poolIdStr).length > 0) {
                poolId = parseScientificNotation(poolIdStr);
            }
        } catch {
            // No poolId provided, compute it using the known pool generation formula
            string memory rateModelKeyPath = "$.InitializePool.rateModelKey";
            bytes32 rateModelKey = vm.parseJsonBytes32(
                config,
                rateModelKeyPath
            );
            address owner = vm.parseJsonAddress(
                config,
                "$.InitializePool.owner"
            );

            // Replicate the poolId computation from the Pool contract
            poolId = uint256(
                keccak256(abi.encodePacked(owner, asset, rateModelKey))
            );
        }
    }
}
