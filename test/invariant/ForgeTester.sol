// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import { OracleHandler } from "./handlers/OracleHandler.sol";
import { PoolHandler } from "./handlers/PoolHandler.sol";
import { PositionManagerHandler } from "./handlers/PositionManagerHandler.sol";
import { SuperPoolHandler } from "./handlers/SuperPoolHandler.sol";
import "forge-std/console2.sol";

contract FoundryTester is PoolHandler, PositionManagerHandler, SuperPoolHandler, OracleHandler {
    function setUp() public {
        setup();
    }

    function test_replay() public {
        superPool_SP_56(6748993879828823428794028936221728208554924626727578398788150828578681249347,236324479555916070066126971065556896106818971737443338530896100985915146482,2895468914658212499868736793802822326302787458121402727959461548738418218881,45414572,113052218);
    }
}