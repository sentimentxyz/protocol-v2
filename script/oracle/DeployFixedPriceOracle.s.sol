// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {FixedPriceOracle} from "src/oracle/FixedPriceOracle.sol";

contract DeployFixedPriceOracle is Script {
    FixedPriceOracle oracle;

    function run() public {
        uint256 price = vm.envUint("FIXED_PRICE");
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new FixedPriceOracle(price);
    }
}
