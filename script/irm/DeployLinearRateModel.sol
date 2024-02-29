// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {LinearRateModel} from "src/irm/LinearRateModel.sol";

contract DeployLinearRateModel is Script {
    LinearRateModel rateModel;

    function run() public {
        uint256 minRate = vm.envUint("MIN_RATE");
        uint256 maxRate = vm.envUint("MAX_RATE");
        require(maxRate > minRate, "MAX <= MIN");
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        rateModel = new LinearRateModel(minRate, maxRate);
    }
}
