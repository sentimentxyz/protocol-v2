// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { ZeroOracle } from "src/oracle/ZeroOracle.sol";

contract DeployZeroOracle is Script {
    ZeroOracle oracle;

    function run() public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new ZeroOracle();
    }
}
