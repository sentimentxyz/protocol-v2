// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {RiskEngine} from "src/RiskEngine.sol";

contract SetLtv is Script {
    function run() public {
        RiskEngine riskEngine = RiskEngine(vm.envAddress("RISK_ENGINE"));

        address pool = vm.envAddress("SET_LTV_POOL");
        address asset = vm.envAddress("SET_ORACLE_ASSET");
        uint256 ltv = vm.envUint("SET_ORACLE_LTV");

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        riskEngine.setLtv(pool, asset, ltv);
    }
}
