// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseScript} from "../BaseScript.s.sol";
import {SuperPoolFactory} from "src/SuperPoolFactory.sol";

contract DeploySuperPool is BaseScript {
    address superPoolFactory;

    function run() public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        superPoolFactory = new SuperPoolFactory();
    }
}
