// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {FixedRateModel} from "src/irm/FixedRateModel.sol";

contract DeployFixedRateModel is Script {
    FixedRateModel rateModel;

    function run() public {
        uint256 fixedRate = vm.envUint("FIXED_RATE");
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        rateModel = new FixedRateModel(fixedRate);
    }
}
