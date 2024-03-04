// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Pool} from "src/Pool.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {Deploy, DeployParams} from "script/Deploy.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract BaseTest is Test {
    uint256 constant MAX_NUM = type(uint144).max;

    Deploy public protocol;

    function setUp() public virtual {
        string memory path =
            string.concat(vm.projectRoot(), "/script/config/", vm.toString(block.chainid), "/config.json");

        if (vm.parseJsonAddress(vm.readFile(path), "$.Deploy.owner") != address(this)) {
            vm.writeJson(vm.toString(address(this)), path, "$.Deploy.owner");
        }

        protocol = new Deploy();
        protocol.run();
    }
}

contract MintableToken is MockERC20 {
    constructor() {
        MockERC20.initialize("TEST", "TEST", 18);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
