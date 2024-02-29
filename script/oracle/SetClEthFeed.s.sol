// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ChainlinkEthOracle} from "src/oracle/ChainlinkEthOracle.sol";

contract SetClEthFeed is Script {
    function run() public {
        ChainlinkEthOracle oracle = ChainlinkEthOracle(vm.envAddress("CL_ETH_ORACLE"));
        address asset = vm.envAddress("ASSET");
        address feed = vm.envAddress("CL_ETH_FEED");
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle.setFeed(asset, feed);
    }
}
