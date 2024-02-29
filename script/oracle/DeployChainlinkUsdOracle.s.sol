// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ChainlinkUsdOracle} from "src/oracle/ChainlinkUsdOracle.sol";

contract DeployChainlinkUsdOracle is Script {
    ChainlinkUsdOracle oracle;

    function run() public {
        address owner = vm.envAddress("OWNER");
        address ethUsdFeed = vm.envAddress("ETH_USD_FEED");
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new ChainlinkUsdOracle(owner, ethUsdFeed);
    }
}
