// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "../BaseScript.s.sol";
import { StringUtils } from "../StringUtils.s.sol";
import { console2 } from "forge-std/console2.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { SuperPoolFactory } from "src/SuperPoolFactory.sol";

contract DeploySuperPool is BaseScript, StringUtils {
    address superPoolFactory;

    address owner;
    address asset;
    address feeRecipient;
    uint256 fee;
    uint256 superPoolCap;
    uint256 initialDepositAmt;
    string name;
    string symbol;

    function run() public {
        getParams();

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        IERC20(asset).approve(superPoolFactory, initialDepositAmt);
        address superPool = SuperPoolFactory(superPoolFactory).deploySuperPool(
            owner, asset, feeRecipient, fee, superPoolCap, initialDepositAmt, name, symbol
        );
        console2.log("SuperPool: ", superPool);
        vm.stopBroadcast();
    }

    function getParams() internal {
        string memory config = getConfig();

        superPoolFactory = vm.parseJsonAddress(config, "$.DeploySuperPool.superPoolFactory");
        owner = vm.parseJsonAddress(config, "$.DeploySuperPool.owner");
        asset = vm.parseJsonAddress(config, "$.DeploySuperPool.asset");
        feeRecipient = vm.parseJsonAddress(config, "$.DeploySuperPool.feeRecipient");

        // Parse numeric parameters with scientific notation support
        string memory feeStr = vm.parseJsonString(config, "$.DeploySuperPool.fee");
        string memory superPoolCapStr = vm.parseJsonString(config, "$.DeploySuperPool.superPoolCap");
        string memory initialDepositAmtStr = vm.parseJsonString(config, "$.DeploySuperPool.initialDepositAmt");

        fee = parseScientificNotation(feeStr);
        superPoolCap = parseScientificNotation(superPoolCapStr);
        initialDepositAmt = parseScientificNotation(initialDepositAmtStr);

        name = vm.parseJsonString(config, "$.DeploySuperPool.name");
        symbol = vm.parseJsonString(config, "$.DeploySuperPool.symbol");

        console2.log("symbol: ", symbol);
        console2.log("name: ", name);
        console2.log("initialDepositAmt: ", initialDepositAmt);
        console2.log("superPoolCap: ", superPoolCap);
        console2.log("fee: ", fee);
        console2.log("feeRecipient: ", feeRecipient);
        console2.log("asset: ", asset);
        console2.log("owner: ", owner);
        console2.log("superPoolFactory: ", superPoolFactory);
    }
}
