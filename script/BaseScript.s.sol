// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

contract BaseScript is Script {
    function getConfig() public view returns (string memory) {
        string memory path = string.concat(
            vm.projectRoot(), "/script/config/", vm.toString(block.chainid), "/", vm.envString("CONFIG"), ".json"
        );
        return vm.readFile(path);
    }

    function getLogPathBase() public view returns (string memory) {
        return string.concat(vm.projectRoot(), "/script/log/", vm.toString(block.chainid), "/");
    }
}
