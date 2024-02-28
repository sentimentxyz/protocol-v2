// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Pool} from "src/Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {Deploy} from "script/Deploy.s.sol";

contract BaseTest is Test {
    uint256 constant BIG_NUMBER = type(uint144).max;

    Deploy public deploy;

    function setUp() public virtual {
        vm.setEnv("OWNER", vm.toString(address(this)));
        deploy = new Deploy();
        deploy.run();
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
