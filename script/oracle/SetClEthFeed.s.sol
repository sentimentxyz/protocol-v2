// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { ChainlinkEthOracle } from "src/oracle/ChainlinkEthOracle.sol";

contract SetClEthFeed is BaseScript {
    address feed;
    address asset;
    ChainlinkEthOracle oracle;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle.setFeed(asset, feed);
        console2.log("SetClEthFeed: ", asset, feed);
    }

    function getParams() internal {
        string memory config = getConfig();

        feed = vm.parseJsonAddress(config, "$.SetClEthFeed.feed");
        asset = vm.parseJsonAddress(config, "$.SetClEthFeed.asset");
        oracle = ChainlinkEthOracle(vm.parseJsonAddress(config, "$.SetClEthFeed.oracle"));
    }
}
