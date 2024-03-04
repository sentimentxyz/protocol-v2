// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

contract BaseScript is Script {
    function getConfig() public view returns (string memory) {
        return vm.readFile(string.concat(vm.projectRoot(), "/script/config/", vm.envString("CONFIG"), ".json"));
    }
}
