// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseScript} from "../BaseScript.s.sol";
import {SuperPool} from "src/SuperPool.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeploySuperPool is BaseScript {
    string name;
    string symbol;
    address asset;
    address owner;
    address allocator;
    uint256 protocolFee;
    uint256 totalPoolCap;

    address superPool;
    address superPoolImpl;

    function run() public {
        getParams();
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        superPoolImpl = address(new SuperPool());
        superPool = address(new TransparentUpgradeableProxy(superPoolImpl, owner, new bytes(0)));
        SuperPool(superPool).initialize(asset, totalPoolCap, protocolFee, allocator, name, symbol);
        vm.stopBroadcast();
    }

    function getParams() internal {
        string memory config = getConfig();

        name = vm.parseJsonString(config, "$.DeploySuperPool.name");
        asset = vm.parseJsonAddress(config, "$.DeploySuperPool.asset");
        owner = vm.parseJsonAddress(config, "$.DeploySuperPool.owner");
        symbol = vm.parseJsonString(config, "$.DeploySuperPool.symbol");
        allocator = vm.parseJsonAddress(config, "$.DeploySuperPool.allocator");
        protocolFee = vm.parseJsonUint(config, "$.DeploySuperPool.protocolFee");
        totalPoolCap = vm.parseJsonUint(config, "$.DeploySuperPool.totalPoolCap");
    }
}
