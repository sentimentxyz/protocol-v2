// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseScript} from "../BaseScript.s.sol";
import {PoolFactory, PoolDeployParams} from "src/PoolFactory.sol";

contract DeployPool is BaseScript {
    PoolFactory poolFactory;
    PoolDeployParams params;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        poolFactory.deployPool(params);
    }

    function getParams() internal {
        string memory config = getConfig();

        poolFactory = PoolFactory(vm.parseJsonAddress(config, "$.DeployPool.poolFactory"));

        params.name = vm.parseJsonString(config, "$.DeployPool.name");
        params.asset = vm.parseJsonAddress(config, "$.DeployPool.asset");
        params.symbol = vm.parseJsonString(config, "$.DeployPool.symbol");
        params.poolCap = vm.parseJsonUint(config, "$.DeployPool.poolCap");
        params.rateModel = vm.parseJsonAddress(config, "$.DeployPool.rateModel");
        params.originationFee = vm.parseJsonUint(config, "$.DeployPool.originationFee");
    }
}
