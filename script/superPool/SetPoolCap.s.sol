// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SuperPool} from "src/SuperPool.sol";
import {BaseScript} from "../BaseScript.s.sol";

contract SetPoolCap is BaseScript {
    uint256 poolId;
    uint256 poolCap;
    SuperPool superPool;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        superPool.setPoolCap(poolId, poolCap);
    }

    function getParams() internal {
        string memory config = getConfig();

        poolId = vm.parseJsonUint(config, "$.SetPoolCap.pool");
        poolCap = vm.parseJsonUint(config, "$.SetPoolCap.poolCap");
        superPool = SuperPool(vm.parseJsonAddress(config, "$.SetPoolCap.superPool"));
    }
}
