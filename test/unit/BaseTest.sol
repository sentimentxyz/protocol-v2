// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {Pool} from "src/Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {Deploy} from "script/Deploy.s.sol";

contract BaseTest is Test {
    Deploy public deploy;

    function setUp() public virtual {
        deploy = new Deploy();

        deploy.run(address(this));
    }
}
