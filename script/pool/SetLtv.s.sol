// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import {RiskEngine} from "src/RiskEngine.sol";

contract SetLtv is BaseScript {
    uint256 ltv;
    address pool;
    address asset;

    RiskEngine riskEngine;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        riskEngine.requestLtvUpdate(pool, asset, ltv);
        riskEngine.acceptLtvUpdate(pool, asset);
    }

    function getParams() internal {
        string memory config = getConfig();

        ltv = vm.parseJsonUint(config, "$.SetLtv.ltv");
        pool = vm.parseJsonAddress(config, "$.SetLtv.pool");
        asset = vm.parseJsonAddress(config, "$.SetLtv.asset");
        riskEngine = RiskEngine(vm.parseJsonAddress(config, "$.SetLtv.riskEngine"));
    }
}
