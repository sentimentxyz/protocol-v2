// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {SuperPool} from "src/SuperPool.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

struct SuperPoolDeployParams {
    string name;
    string symbol;
    address asset;
    address owner;
    address allocator;
    uint256 protocolFee;
    uint256 totalPoolCap;
}

contract DeploySuperPool is Script {
    address superPool;
    address superPoolImpl;

    function run() public {
        SuperPoolDeployParams memory params = getSuperPoolDeployParams();
        deploy(params);
    }

    function deploy(SuperPoolDeployParams memory params) public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        superPoolImpl = address(new SuperPool());
        superPool = address(new TransparentUpgradeableProxy(superPoolImpl, params.owner, new bytes(0)));
        SuperPool(superPool).initialize(
            params.asset, params.totalPoolCap, params.protocolFee, params.allocator, params.name, params.symbol
        );
        vm.stopBroadcast();
    }

    function getSuperPoolDeployParams() internal view returns (SuperPoolDeployParams memory params) {
        string memory path =
            string.concat(vm.projectRoot(), "/script/config/", vm.toString(block.chainid), "/superPool.json");
        string memory config = vm.readFile(path);

        params.name = vm.parseJsonString(config, "$.name");
        params.asset = vm.parseJsonAddress(config, "$.asset");
        params.owner = vm.parseJsonAddress(config, "$.owner");
        params.symbol = vm.parseJsonString(config, "$.symbol");
        params.allocator = vm.parseJsonAddress(config, "$.allocator");
        params.protocolFee = vm.parseJsonUint(config, "$.protocolFee");
        params.totalPoolCap = vm.parseJsonUint(config, "$.totalPoolCap");
    }
}
