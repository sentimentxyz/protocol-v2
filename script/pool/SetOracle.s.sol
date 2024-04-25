// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import {RiskEngine} from "src/RiskEngine.sol";

contract SetOracle is BaseScript {
    address pool;
    address asset;
    address oracle;

    RiskEngine riskEngine;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        riskEngine.requestOracleUpdate(pool, asset, oracle);
        riskEngine.acceptOracleUpdate(pool, asset);
    }

    function getParams() internal {
        string memory config = getConfig();

        pool = vm.parseJsonAddress(config, "$.SetOracle.pool");
        asset = vm.parseJsonAddress(config, "$.SetOracle.asset");
        oracle = vm.parseJsonAddress(config, "$.SetOracle.oracle");
        riskEngine = RiskEngine(vm.parseJsonAddress(config, "$.SetOracle.riskEngine"));
    }
}
