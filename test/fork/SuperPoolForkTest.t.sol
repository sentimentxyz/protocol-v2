// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MockERC20 } from "../mocks/MockERC20.sol";
import { BaseForkTest } from "./BaseForkTest.t.sol";
import { Pool } from "src/Pool.sol";
import { SuperPool } from "src/SuperPool.sol";

contract SuperPoolForkTest is BaseForkTest {
    function setUp() public override {
        super.setUp();
    }

    function testForkUsdcSuperPoolDepositWithdraw() public {
        _depositAndWithdrawSuperPool(100e6, "$.usdc", "$.usdc-1", "$.seUSDC");
    }

    function testForkWethSuperPoolDepositWithdraw() public {
        _depositAndWithdrawSuperPool(10e18, "$.weth", "$.weth-1", "$.seWETH");
    }

    function _depositAndWithdrawSuperPool(
        uint256 amt,
        string memory assetKey,
        string memory basePoolKey,
        string memory superPoolKey
    ) internal {
        sender = vm.parseJsonAddress(config, "$.sender");
        pool = Pool(vm.parseJsonAddress(config, "$.pool"));
        address asset = vm.parseJsonAddress(config, assetKey);
        uint256 basePool = vm.parseJsonUint(config, basePoolKey);
        SuperPool superPool = SuperPool(vm.parseJsonAddress(config, superPoolKey));

        MockERC20(asset).mint(sender, amt);

        vm.startPrank(sender);
        MockERC20(asset).approve(address(superPool), amt);
        uint256 shares = superPool.deposit(amt, sender);
        vm.stopPrank();

        assertEq(pool.getTotalAssets(basePool), amt);
        assertEq(superPool.balanceOf(sender), shares);
        assertEq(MockERC20(asset).balanceOf(address(sender)), 0);
        assertEq(MockERC20(asset).balanceOf(address(superPool)), 0);

        vm.prank(sender);
        superPool.withdraw(amt, sender, sender);

        assertEq(superPool.balanceOf(sender), 0);
        assertEq(pool.getTotalAssets(basePool), 0);
        assertEq(MockERC20(asset).balanceOf(address(sender)), amt);
        assertEq(MockERC20(asset).balanceOf(address(superPool)), 0);
    }
}
