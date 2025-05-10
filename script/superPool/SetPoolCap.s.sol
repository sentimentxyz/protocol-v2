// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "../BaseScript.s.sol";
import { StringUtils } from "../StringUtils.s.sol";
import { console2 } from "forge-std/console2.sol";
import { SuperPool } from "src/SuperPool.sol";

contract SetPoolCap is BaseScript, StringUtils {
    uint256 poolId;
    uint256 poolCap;
    SuperPool superPool;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        superPool.addPool(poolId, poolCap);
        console2.log("SetPoolCap: ", address(superPool), poolId, poolCap);
    }

    function getParams() internal {
        string memory config = getConfig();

        poolId = vm.parseJsonUint(config, "$.SetPoolCap.poolId");

        // Parse poolCap with scientific notation support
        string memory poolCapStr = vm.parseJsonString(config, "$.SetPoolCap.poolCap");
        poolCap = parseScientificNotation(poolCapStr);

        superPool = SuperPool(vm.parseJsonAddress(config, "$.SetPoolCap.superPool"));
    }
}
