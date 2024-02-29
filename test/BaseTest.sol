// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Pool} from "src/Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {Deploy, DeployParams} from "script/Deploy.s.sol";

contract BaseTest is Test {
    uint256 constant MAX_NUM = type(uint144).max;

    Deploy public deploy;

    function setUp() public virtual {
        DeployParams memory params = DeployParams({
            owner: address(this),
            minLtv: 0,
            maxLtv: type(uint256).max,
            liqFee: 0,
            closeFactor: 5e17,
            liqDiscount: 2e17
        });
        deploy = new Deploy();
        deploy.run(params);
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
