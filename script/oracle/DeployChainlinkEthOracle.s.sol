// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import {ChainlinkEthOracle} from "src/oracle/ChainlinkEthOracle.sol";

contract DeployChainlinkEthOracle is BaseScript {
    address owner;
    ChainlinkEthOracle oracle;

    function run() public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new ChainlinkEthOracle(owner);
    }

    function getParams() internal {
        string memory config = getConfig();

        owner = vm.parseJsonAddress(config, "$.DeployChainLinkEthOracle.owner");
        oracle = ChainlinkEthOracle(vm.parseJsonAddress(config, "$.DeployChainLinkEthOracle.oracle"));
    }
}
