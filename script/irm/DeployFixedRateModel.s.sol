// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { FixedRateModel } from "src/irm/FixedRateModel.sol";

contract DeployFixedRateModel is BaseScript {
    uint256 rate;
    FixedRateModel rateModel;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        rateModel = new FixedRateModel(rate);
    }

    function getParams() internal {
        string memory config = getConfig();

        rate = vm.parseJsonUint(config, "$.DeployFixedRateModel.rate");
        rateModel = FixedRateModel(vm.parseJsonAddress(config, "$.DeployFixedRateModel.rateModel"));
    }
}
