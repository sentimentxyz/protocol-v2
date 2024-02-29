// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {PoolFactory, PoolDeployParams} from "src/PoolFactory.sol";

contract DeployPool is Script {
    function run() public {
        PoolDeployParams memory params = getPoolDeployParams();
        deploy(params);
    }

    function deploy(PoolDeployParams memory params) public {
        PoolFactory poolFactory = PoolFactory(vm.parseJsonAddress(getConfig(), "$.poolFactory"));
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        poolFactory.deployPool(params);
    }

    function getPoolDeployParams() internal view returns (PoolDeployParams memory params) {
        string memory config = getConfig();

        params.name = vm.parseJsonString(config, "$.name");
        params.asset = vm.parseJsonAddress(config, "$.asset");
        params.symbol = vm.parseJsonString(config, "$.symbol");
        params.poolCap = vm.parseJsonUint(config, "$.poolCap");
        params.rateModel = vm.parseJsonAddress(config, "$.rateModel");
        params.originationFee = vm.parseJsonUint(config, "$.originationFee");
    }

    function getConfig() internal view returns (string memory config) {
        string memory path =
            string.concat(vm.projectRoot(), "/script/config/", vm.toString(block.chainid), "/pool.json");
        config = vm.readFile(path);
    }
}
