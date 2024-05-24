// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";

contract DeployFixedPriceOracle is BaseScript {
    uint256 price;
    FixedPriceOracle oracle;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new FixedPriceOracle(price);
    }

    function getParams() internal {
        string memory config = getConfig();
        price = vm.parseJsonUint(config, "$.DeployFixedPriceOracle.price");
    }
}
