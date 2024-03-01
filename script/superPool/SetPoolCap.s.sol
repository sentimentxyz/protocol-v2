// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {SuperPool} from "src/SuperPool.sol";

contract SetPoolCap is Script {
    function run() public {
        SuperPool superPool = SuperPool(vm.envAddress("SET_POOL_CAP_SUPERPOOL"));

        address pool = vm.envAddress("SET_POOL_CAP_POOL");
        uint256 poolCap = vm.envUint("SET_POOL_CAP_POOLCAP");

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        superPool.setPoolCap(pool, poolCap);
    }
}
