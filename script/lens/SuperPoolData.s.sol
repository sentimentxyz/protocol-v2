// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { SuperPoolLens } from "src/lens/SuperPoolLens.sol";

contract SuperPoolData is BaseScript {
    function run() public view {
        SuperPoolLens superPoolLens = SuperPoolLens(0x120659e930795E87a860ee853066004bF9E44479);
        superPoolLens.getSuperPoolData(0xD7Fc4E31313fE889764313341d08229047db2b44);
    }
}
