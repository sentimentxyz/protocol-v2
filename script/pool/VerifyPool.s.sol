// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "../BaseScript.s.sol";
import { StringUtils } from "../StringUtils.s.sol";
import { console2 } from "forge-std/console2.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { Pool } from "src/Pool.sol";
import { Registry } from "src/Registry.sol";
import { RiskEngine } from "src/RiskEngine.sol";

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
        _getParams();

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

        // Get token decimals and symbol
        uint8 assetDecimals = _getTokenDecimals(poolAsset);
        string memory assetSymbol = _getTokenSymbol(poolAsset);

        // Display verification information in separate functions to reduce stack depth
        _displayBasicInfo(owner, poolAsset, rateModel, assetDecimals, assetSymbol, pool, poolId);
        _displayAmounts(
            depositCap,
            borrowCap,
            totalAssetsWithInterest,
            totalBorrowsWithInterest,
            liquidAssets,
            assetDecimals,
            assetSymbol
        );
        _displayOracleInfo(assetOracle);
        _displayVerificationResult(poolAsset, depositCap, borrowCap, rateModel, totalAssetsWithInterest, asset);
    }

    /// @notice Helper function to get token symbol from ERC20 tokens
    /// @param tokenAddress The address of the token
    /// @return symbol The token symbol, defaults to "Unknown" if call fails
    function _getTokenSymbol(address tokenAddress) internal view returns (string memory symbol) {
        try IERC20Metadata(tokenAddress).symbol() returns (string memory tokenSymbol) {
            return tokenSymbol;
        } catch {
            return "Unknown";
        }
    }

    /// @notice Display basic pool information
    function _displayBasicInfo(
        address owner,
        address poolAsset,
        address rateModel,
        uint8 assetDecimals,
        string memory assetSymbol,
        address poolAddress,
        uint256 poolId_
    )
        internal
        pure
    {
        console2.log("=== Pool Verification ===");
        console2.log("Pool Contract: ", poolAddress);
        console2.log("Pool ID: ", poolId_);
        console2.log("Owner: ", owner);
        console2.log("Asset: ", poolAsset);
        console2.log("Asset Symbol: ", assetSymbol);
        console2.log("Asset Decimals: ", assetDecimals);
        console2.log("Rate Model Address: ", rateModel);
    }

    /// @notice Display amounts with correct formatting
    function _displayAmounts(
        uint256 depositCap,
        uint256 borrowCap,
        uint256 totalAssetsWithInterest,
        uint256 totalBorrowsWithInterest,
        uint256 liquidAssets,
        uint8 assetDecimals,
        string memory assetSymbol
    )
        internal
        pure
    {
        // Format values with proper decimals
        string memory formattedDepositCap = _formatWithDecimals(depositCap, assetDecimals);
        string memory formattedBorrowCap = _formatWithDecimals(borrowCap, assetDecimals);
        string memory formattedTotalAssets = _formatWithDecimals(totalAssetsWithInterest, assetDecimals);
        string memory formattedTotalBorrows = _formatWithDecimals(totalBorrowsWithInterest, assetDecimals);
        string memory formattedLiquidAssets = _formatWithDecimals(liquidAssets, assetDecimals);

        // Display formatted amounts with string concatenation to reduce parameter count
        console2.log(string.concat("Deposit Cap: ", formattedDepositCap, " ", assetSymbol));
        console2.log(string.concat("Borrow Cap: ", formattedBorrowCap, " ", assetSymbol));
        console2.log(string.concat("Total Assets (with interest): ", formattedTotalAssets, " ", assetSymbol));
        console2.log(string.concat("Total Borrows (with interest): ", formattedTotalBorrows, " ", assetSymbol));
        console2.log(string.concat("Liquid Assets: ", formattedLiquidAssets, " ", assetSymbol));

        // Also display raw values for verification
        console2.log("Deposit Cap (raw): ", depositCap);
        console2.log("Borrow Cap (raw): ", borrowCap);
        console2.log("Total Assets (raw): ", totalAssetsWithInterest);
        console2.log("Total Borrows (raw): ", totalBorrowsWithInterest);
        console2.log("Liquid Assets (raw): ", liquidAssets);
    }

    /// @notice Display oracle information
    function _displayOracleInfo(address assetOracle) internal pure {
        console2.log("Asset Oracle: ", assetOracle);

        if (address(assetOracle) == address(0)) console2.log("WARNING: No oracle registered for asset!");
        else console2.log("Oracle is properly registered");
    }

    /// @notice Display verification result
    function _displayVerificationResult(
        address poolAsset,
        uint256 depositCap,
        uint256 borrowCap,
        address rateModel,
        uint256 totalAssetsWithInterest,
        address expectedAsset
    )
        internal
        pure
    {
        // Check if initial deposit was successful
        if (totalAssetsWithInterest == 0) console2.log("WARNING: No deposits in the pool!");
        else console2.log("Initial deposit confirmed");

        // Configuration success summary
        bool configSuccess = (
            poolAsset == expectedAsset && depositCap > 0 && borrowCap > 0 && rateModel != address(0)
                && totalAssetsWithInterest > 0
        );

        console2.log("=== Verification Result ===");
        console2.log("Pool initialized correctly: ", configSuccess ? "YES" : "NO");
    }

    function _getParams() internal {
        string memory config = getConfig();

        // Get basic params from InitializePool section
        pool = vm.parseJsonAddress(config, "$.InitializePool.pool");
        asset = vm.parseJsonAddress(config, "$.InitializePool.asset");

        // Get addresses of core contracts
        registry = vm.parseJsonAddress(config, "$.VerifyPool.registry");
        riskEngine = vm.parseJsonAddress(config, "$.VerifyPool.riskEngine");

        // If we already know the poolId, read it, otherwise we need to compute it
        string memory poolIdPath = "$.VerifyPool.poolId";

        try vm.parseJsonString(config, poolIdPath) returns (string memory poolIdStr) {
            if (bytes(poolIdStr).length > 0) poolId = parseScientificNotation(poolIdStr);
        } catch {
            // No poolId provided, compute it using the known pool generation formula
            string memory rateModelKeyPath = "$.InitializePool.rateModelKey";
            bytes32 rateModelKey = vm.parseJsonBytes32(config, rateModelKeyPath);
            address owner = vm.parseJsonAddress(config, "$.InitializePool.owner");

            // Replicate the poolId computation from the Pool contract
            poolId = uint256(keccak256(abi.encodePacked(owner, asset, rateModelKey)));
        }
    }

    /// @notice Helper function to get token decimals from ERC20 tokens
    /// @param tokenAddress The address of the token
    /// @return decimals The number of decimals the token uses, defaults to 18 if call fails
    function _getTokenDecimals(address tokenAddress) internal view returns (uint8 decimals) {
        try IERC20Metadata(tokenAddress).decimals() returns (uint8 tokenDecimals) {
            return tokenDecimals;
        } catch {
            // If the call fails, default to 18 decimals
            return 18;
        }
    }

    /// @notice Format a token amount with proper decimals for human-readable output
    /// @param amount The raw token amount
    /// @param decimals The token's decimal places
    /// @return result The formatted string with proper decimal representation
    function _formatWithDecimals(uint256 amount, uint8 decimals) internal pure returns (string memory result) {
        if (amount == 0) return "0";

        // First convert to a string
        string memory amountStr = vm.toString(amount);
        bytes memory amountBytes = bytes(amountStr);

        // If the length is less than or equal to decimals, we need to pad with leading zeros
        if (amountBytes.length <= decimals) {
            // Create the fractional part with appropriate padding
            string memory fractionalPart = "";
            for (uint8 i = 0; i < decimals - amountBytes.length; i++) {
                fractionalPart = string(abi.encodePacked(fractionalPart, "0"));
            }
            fractionalPart = string(abi.encodePacked(fractionalPart, amountStr));
            return string(abi.encodePacked("0.", fractionalPart));
        } else {
            // Split into integer and fractional parts
            uint8 integerLength = uint8(amountBytes.length) - decimals;

            // Extract integer part
            bytes memory integerBytes = new bytes(integerLength);
            for (uint8 i = 0; i < integerLength; i++) {
                integerBytes[i] = amountBytes[i];
            }

            // Extract fractional part if any
            string memory fractionalPart = "";
            if (decimals > 0) {
                bytes memory fractionalBytes = new bytes(decimals);
                for (uint8 i = 0; i < decimals; i++) {
                    fractionalBytes[i] = amountBytes[integerLength + i];
                }
                fractionalPart = string(abi.encodePacked(".", string(fractionalBytes)));
            }

            return string(abi.encodePacked(string(integerBytes), fractionalPart));
        }
    }
}
