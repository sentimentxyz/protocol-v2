// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {RiskEngine} from "src/RiskEngine.sol";

contract SetOracle is Script {
    function run() public {
        RiskEngine riskEngine = RiskEngine(vm.envAddress("RISK_ENGINE"));

        address pool = vm.envAddress("SET_ORACLE_POOL");
        address asset = vm.envAddress("SET_ORACLE_ASSET");
        address oracle = vm.envAddress("SET_ORACLE_ORACLE");

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        riskEngine.setOracle(pool, asset, oracle);
    }
}
