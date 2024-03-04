// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import {RiskEngine} from "src/RiskEngine.sol";

contract ToggleOracleStatus is BaseScript {
    address oracle;
    RiskEngine riskEngine;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        riskEngine.toggleOracleStatus(oracle);
    }

    function getParams() internal {
        string memory config = getConfig();

        oracle = vm.parseJsonAddress(config, "$.ToggleOracleStatus.oracle");
        riskEngine = RiskEngine(vm.parseJsonAddress(config, "$.ToggleOracleStatus.riskEngine"));
    }
}
