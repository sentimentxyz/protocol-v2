// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { KinkedRateModel } from "src/irm/KinkedRateModel.sol";

contract DeployKinkedRateModel is BaseScript {
    uint256 minRate;
    uint256 slope1;
    uint256 slope2;
    uint256 optimalUtil;

    KinkedRateModel rateModel;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        rateModel = new KinkedRateModel(minRate, slope1, slope2, optimalUtil);
        console2.log("FixedRateModel: ", address(rateModel));
    }

    function getParams() internal {
        string memory config = getConfig();

        minRate = vm.parseJsonUint(config, "$.DeployKinkedRateModel.minRate");
        slope1 = vm.parseJsonUint(config, "$.DeployKinkedRateModel.slope1");
        slope2 = vm.parseJsonUint(config, "$.DeployKinkedRateModel.slope2");
        optimalUtil = vm.parseJsonUint(config, "$.DeployKinkedRateModel.optimalUtil");
    }
}
