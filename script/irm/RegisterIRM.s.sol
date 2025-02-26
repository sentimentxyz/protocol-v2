// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";

import { console2 } from "forge-std/console2.sol";
import { Registry } from "src/Registry.sol";

contract RegisterIRM is BaseScript {
    bytes32 key;
    address irm;
    Registry registry;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        registry.setRateModel(key, irm);

        console2.log("Registered Key:");
        console2.logBytes32(key);
        console2.log("For IRM: ", irm);
    }

    function getParams() internal {
        string memory config = getConfig();

        key = vm.parseJsonBytes32(config, "$.RegisterIRM.key");
        irm = vm.parseJsonAddress(config, "$.RegisterIRM.irm");
        registry = Registry(vm.parseJsonAddress(config, "$.RegisterIRM.registry"));
    }
}
