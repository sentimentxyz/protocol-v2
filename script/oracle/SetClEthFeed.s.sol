// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { ChainlinkEthOracle } from "src/oracle/ChainlinkEthOracle.sol";

contract SetClEthFeed is BaseScript {
    address feed;
    address asset;
    ChainlinkEthOracle clEthFeed;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        clEthFeed.setFeed(asset, feed);
    }

    function getParams() internal {
        string memory config = getConfig();

        feed = vm.parseJsonAddress(config, "$.SetClEthFeed.feed");
        asset = vm.parseJsonAddress(config, "$.SetClEthFeed.asset");
        clEthFeed = ChainlinkEthOracle(vm.parseJsonAddress(config, "$.SetClEthFeed.asset"));
    }
}
