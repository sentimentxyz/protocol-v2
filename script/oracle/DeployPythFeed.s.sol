// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { PythAggregatorV3 } from "src/lib/PythAggregatorV3.sol";

contract DeployPythFeed is BaseScript {
    PythAggregatorV3 pythAggV3;
    address pyth;
    bytes32 priceId;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        pythAggV3 = new PythAggregatorV3(pyth, priceId);
        console2.log("PythFeed deployed: ", address(pythAggV3));
    }

    function getParams() internal {
        pyth = vm.parseJsonAddress(getConfig(), "$.DeployPythFeed.pyth");
        priceId = vm.parseJsonBytes32(getConfig(), "$.DeployPythFeed.priceId");
    }
}
