// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { SuperPoolFactory } from "src/SuperPoolFactory.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract DeploySuperPool is BaseScript {
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
        //MockERC20(asset).mint(owner, initialDepositAmt);
        MockERC20(asset).approve(superPoolFactory, initialDepositAmt);
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
        fee = vm.parseJsonUint(config, "$.DeploySuperPool.fee");
        superPoolCap = vm.parseJsonUint(config, "$.DeploySuperPool.superPoolCap");
        initialDepositAmt = vm.parseJsonUint(config, "$.DeploySuperPool.initialDepositAmt");
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
