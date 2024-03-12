// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import {Pool} from "src/Pool.sol";

contract SetPoolIrm is BaseScript {
    address pool;
    address rateModel;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        Pool(pool).setRateModel(rateModel);
    }

    function getParams() internal {
        string memory config = getConfig();

        pool = vm.parseJsonAddress(config, "$.SetPoolIrm.pool");
        rateModel = vm.parseJsonAddress(config, "$.SetPoolIrm.rateModel");
    }
}