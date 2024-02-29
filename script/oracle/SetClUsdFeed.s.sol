// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ChainlinkUsdOracle} from "src/oracle/ChainlinkUsdOracle.sol";

contract SetClEthFeed is Script {
    function run() public {
        ChainlinkUsdOracle oracle = ChainlinkUsdOracle(vm.envAddress("CL_USD_ORACLE"));
        address asset = vm.envAddress("ASSET");
        address feed = vm.envAddress("CL_USD_FEED");
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle.setFeed(asset, feed);
    }
}
