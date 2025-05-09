// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "./BaseScript.s.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console2 } from "forge-std/console2.sol";
import { Pool } from "src/Pool.sol";
import { Position } from "src/Position.sol";
import { Action, Operation, PositionManager } from "src/PositionManager.sol";
import { RiskEngine } from "src/RiskEngine.sol";

/**
 * @title WithdrawToThreshold
 * @notice Script to withdraw assets from a position and bring health factor close to liquidation threshold
 */
contract WithdrawToThreshold is BaseScript {
    // Target position to withdraw from
    address public constant POSITION = 0xBeFB971f0964E9aEb04a086D2f108E8bE482fF92;
    // Target health factor (just above liquidation threshold)
    uint256 public constant TARGET_HEALTH_FACTOR = 0.9999e18;
    // Margin above target to avoid liquidation (0.5%)
    uint256 public constant SAFETY_MARGIN = 0.005e18;

    // Contract addresses
    address public positionManager;
    address public riskEngine;
    address public positionOwner;

    function run() public {
        getParams();

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // Get position assets
        address[] memory assets = Position(payable(POSITION)).getPositionAssets();

        // Get current health factor
        uint256 initialHealthFactor = RiskEngine(riskEngine).getPositionHealthFactor(POSITION);
        console2.log("Initial health factor:");
        console2.log(initialHealthFactor);
        console2.log("%");

        // Handle case where health factor is already below target
        if (initialHealthFactor <= TARGET_HEALTH_FACTOR) {
            console2.log("Health factor already at or below target, no withdrawal needed");
            vm.stopBroadcast();
            return;
        }

        // Find asset with highest value to withdraw
        (address targetAsset, uint256 withdrawAmount) = calculateOptimalWithdrawal(assets);
        console2.log("Optimal withdraw amount:", withdrawAmount);

        // Transfer assets out of the position
        Action memory action = createTransferAction(targetAsset, positionOwner, withdrawAmount);

        // Process the action
        PositionManager(positionManager).process(POSITION, action);

        // Get final health factor
        uint256 finalHealthFactor = RiskEngine(riskEngine).getPositionHealthFactor(POSITION);
        console2.log("Final health factor:");
        console2.log(finalHealthFactor / 1e16);
        console2.log("%");

        console2.log("Withdrawn:");
        console2.log(withdrawAmount);
        console2.log("of asset:");
        console2.log(targetAsset);
        console2.log("to:");
        console2.log(positionOwner);

        vm.stopBroadcast();
    }

    function calculateOptimalWithdrawal(address[] memory assets)
        internal
        view
        returns (address targetAsset, uint256 withdrawAmount)
    {
        RiskEngine riskEngineContract = RiskEngine(riskEngine);

        // Find asset with highest value
        uint256 highestValue = 0;

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 assetBalance = IERC20(asset).balanceOf(POSITION);
            uint256 valueInEth = riskEngineContract.getValueInEth(asset, assetBalance);

            if (valueInEth > highestValue) {
                highestValue = valueInEth;
                targetAsset = asset;
            }
        }

        // Log highest value asset found
        console2.log("Found target asset with highest value:");
        console2.log(targetAsset);

        // Calculate withdrawal amount using binary search to get close to target
        uint256 balance = IERC20(targetAsset).balanceOf(POSITION);
        uint256 low = 0;
        uint256 high = balance;
        uint256 mid;
        uint256 iterations = 0;
        uint256 maxIterations = 30;

        while (low < high && iterations < maxIterations) {
            mid = (low + high) / 2;

            uint256 healthFactor = calculateHealthFactorAfterWithdrawal(targetAsset, mid);

            if (healthFactor < TARGET_HEALTH_FACTOR) {
                // Withdrawing too much, reduce amount
                high = mid;
            } else if (healthFactor > TARGET_HEALTH_FACTOR + SAFETY_MARGIN) {
                // Not withdrawing enough, increase amount
                low = mid + 1;
            } else {
                // Found a good amount
                return (targetAsset, mid);
            }

            iterations++;
        }

        // After binary search, choose the best approximation
        return (targetAsset, low);
    }

    function calculateHealthFactorAfterWithdrawal(address asset, uint256 amount) internal view returns (uint256) {
        // Clone RiskEngine's calculation logic but take into account the withdrawal
        RiskEngine riskEngineContract = RiskEngine(riskEngine);

        (uint256 totalAssetValue, uint256 totalDebtValue, uint256 minReqAssetValue) =
            riskEngineContract.getRiskData(POSITION);

        // Calculate value being withdrawn
        uint256 withdrawnValue = riskEngineContract.getValueInEth(asset, amount);

        // Adjust asset value
        totalAssetValue = totalAssetValue > withdrawnValue ? totalAssetValue - withdrawnValue : 0;

        // Calculate new health factor
        if (totalDebtValue == 0) return type(uint256).max; // No debt means infinite health

        if (totalAssetValue <= minReqAssetValue) return 0; // Underwater

        return ((totalAssetValue - minReqAssetValue) * 1e18) / totalDebtValue;
    }

    function createTransferAction(
        address asset,
        address recipient,
        uint256 amount
    )
        internal
        pure
        returns (Action memory)
    {
        bytes memory data = abi.encodePacked(recipient, asset, amount);
        return Action({ op: Operation.Transfer, data: data });
    }

    function getParams() internal {
        //string memory config = getConfig();
        //positionManager = vm.parseJsonAddress(config, "$.WithdrawToThreshold.positionManager");
        //riskEngine = vm.parseJsonAddress(config, "$.WithdrawToThreshold.riskEngine");

        // Use predefined contract addresses if not in config
        if (positionManager == address(0)) positionManager = 0xE019Ce6e80dFe505bca229752A1ad727E14085a4; // HyperEVM
            // Mainnet

        if (riskEngine == address(0)) riskEngine = 0xd22dE451Ba71fA6F06C65962649ba4E2Aea10863; // HyperEVM Mainnet
    }
}
