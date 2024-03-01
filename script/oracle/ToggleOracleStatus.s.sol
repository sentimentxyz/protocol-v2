// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {RiskEngine} from "src/RiskEngine.sol";

contract ToggleOracleStatus is Script {
    function run() public {
        RiskEngine riskEngine = RiskEngine(vm.envAddress("RISK_ENGINE"));
        address oracle = vm.envAddress("ORACLE");
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        riskEngine.toggleOracleStatus(oracle);
    }
}
