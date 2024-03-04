// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import {ChainlinkUsdOracle} from "src/oracle/ChainlinkUsdOracle.sol";

contract DeployChainlinkUsdOracle is BaseScript {
    address owner;
    address ethUsdFeed;
    ChainlinkUsdOracle oracle;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new ChainlinkUsdOracle(owner, ethUsdFeed);
    }

    function getParams() internal {
        string memory config = getConfig();

        owner = vm.parseJsonAddress(config, "$.DeployChainlinkUsdOracle.owner");
        ethUsdFeed = vm.parseJsonAddress(config, "$.DeployChainlinkUsdOracle.ethUsdFeed");
        oracle = ChainlinkUsdOracle(vm.parseJsonAddress(config, "$.DeployChainlinkUsdOracle.oracle"));
    }
}
