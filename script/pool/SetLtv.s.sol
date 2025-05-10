// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { StringUtils } from "../StringUtils.s.sol";
import { console2 } from "forge-std/console2.sol";
import { RiskEngine } from "src/RiskEngine.sol";

contract SetLtv is BaseScript, StringUtils {
    uint256 ltv;
    uint256 poolId;
    address asset;

    RiskEngine riskEngine;

    function run() public {
        getParams();

        require(ltv < 1e18, "LTV < 100%");
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        riskEngine.requestLtvUpdate(poolId, asset, ltv);
        console2.log("Request Ltv Update: ", poolId, asset, ltv);
        if (riskEngine.ltvFor(poolId, asset) == 0) {
            riskEngine.acceptLtvUpdate(poolId, asset);
            console2.log("Set Ltv: ", poolId, asset, ltv);
        }
        vm.stopBroadcast();
    }

    function getParams() internal {
        string memory config = getConfig();

        // Parse ltv with scientific notation support
        string memory ltvStr = vm.parseJsonString(config, "$.SetLtv.ltv");
        ltv = parseScientificNotation(ltvStr);

        poolId = vm.parseJsonUint(config, "$.SetLtv.poolId");
        asset = vm.parseJsonAddress(config, "$.SetLtv.asset");
        riskEngine = RiskEngine(vm.parseJsonAddress(config, "$.SetLtv.riskEngine"));
    }
}
