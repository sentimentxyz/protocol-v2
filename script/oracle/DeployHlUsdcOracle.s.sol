// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { HlUsdcOracle } from "src/oracle/HlUsdcOracle.sol";

contract DeployHlUsdcOracle is BaseScript {
    HlUsdcOracle oracle;

    function run() public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new HlUsdcOracle();
        console2.log("HlUsdcOracle: ", address(oracle));
    }
}
