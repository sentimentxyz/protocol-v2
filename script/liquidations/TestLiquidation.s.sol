// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseScript} from "../BaseScript.s.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {LiquidatePosition} from "./LiquidatePosition.s.sol";

/**
 * @title TestLiquidation
 * @notice Simple test script for the LiquidatePosition script
 * @dev Run with:
 *   forge script script/liquidations/TestLiquidation.s.sol:TestLiquidation --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> -vvv
 */
contract TestLiquidation is BaseScript {
    // Test addresses - update these with actual addresses
    address public constant TEST_POSITION = address(0); // Update with a real position

    function run() external {
        vm.startBroadcast();

        // Create the liquidator script
        LiquidatePosition liquidator = new LiquidatePosition();

        console.log(
            "Created LiquidatePosition script at:",
            address(liquidator)
        );
        console.log("");

        if (TEST_POSITION != address(0)) {
            console.log("Testing position analysis (dry-run)...");

            //liquidator.run(TEST_POSITION);

            // Instead of the above line, we'll call our own function that bypasses the broadcast
            // This lets us analyze the position without needing to have the tokens for liquidation
            _testPositionAnalysis(TEST_POSITION);
        } else {
            console.log(
                "Skipping position analysis - no test position specified"
            );
            console.log(
                "Update TEST_POSITION in the script with a valid position address"
            );
        }

        vm.stopBroadcast();
    }

    // This function simulates LiquidatePosition.run() without the actual liquidation
    function _testPositionAnalysis(address position) internal {
        console.log("Analyzing position:", position);

        // Environment variables for the liquidation script
        // You can change these to match your testing environment
        vm.setEnv("REGISTRY_ADDRESS", vm.envString("REGISTRY_ADDRESS"));
        vm.setEnv(
            "POSITION_MANAGER_ADDRESS",
            vm.envString("POSITION_MANAGER_ADDRESS")
        );
        vm.setEnv("POOL_ADDRESS", vm.envString("POOL_ADDRESS"));
        vm.setEnv("RISK_ENGINE_ADDRESS", vm.envString("RISK_ENGINE_ADDRESS"));
        vm.setEnv("RISK_MODULE_ADDRESS", vm.envString("RISK_MODULE_ADDRESS"));

        // Create a new instance to make sure environment variables are loaded
        LiquidatePosition liquidator = new LiquidatePosition();

        // Call setUp to initialize the contract instances
        // We need to do a bit of Solidity gymnastics here since setUp is not external
        (bool success, ) = address(liquidator).call(
            abi.encodeWithSignature("setUp()")
        );
        require(success, "Setup failed");

        // Test that the setup function works by printing addresses
        console.log("LiquidatePosition script initialized");
        console.log("PositionManager:", liquidator.positionManagerAddr());
        console.log("Pool:", liquidator.poolAddr());
        console.log("RiskEngine:", liquidator.riskEngineAddr());
        console.log("RiskModule:", liquidator.riskModuleAddr());

        console.log("");
        console.log(
            "Test complete!"
        );
        console.log("To perform an actual liquidation, run:");
        console.log(
            'forge script script/liquidations/LiquidatePosition.s.sol:LiquidatePosition --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> -vvv --sig "run(address)" <POSITION_ADDRESS>'
        );
    }
}
