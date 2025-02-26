// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { HyperliquidUsdcOracle } from "src/oracle/HyperliquidUsdcOracle.sol";

contract DeployHlUsdcOracle is BaseScript {
    HyperliquidUsdcOracle oracle;

    function run() public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new HyperliquidUsdcOracle();
        console2.log("HlUsdcOracle: ", address(oracle));
    }
}
