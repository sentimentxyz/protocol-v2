// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ChainlinkEthOracle} from "src/oracle/ChainlinkEthOracle.sol";

contract DeployChainlinkEthOracle is Script {
    ChainlinkEthOracle oracle;

    function run() public {
        address owner = vm.envAddress("OWNER");
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new ChainlinkEthOracle(owner);
    }
}
