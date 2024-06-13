// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MockERC20 } from "../mocks/MockERC20.sol";
import { BaseForkTest } from "./BaseForkTest.t.sol";
import { Pool } from "src/Pool.sol";

contract PoolForkTest is BaseForkTest {
    function setUp() public override {
        super.setUp();
    }

    function testForkUsdcPoolDepositWithdraw() public {
        _depositAndWithdrawPool(100e6, "$.usdc", "$.usdc-1");
    }

    function testForkWethPoolDepositWithdraw() public {
        _depositAndWithdrawPool(10e18, "$.weth", "$.weth-1");
    }

    function _depositAndWithdrawPool(uint256 amt, string memory assetKey, string memory basePoolKey) internal {
        sender = vm.parseJsonAddress(config, "$.sender");
        pool = Pool(vm.parseJsonAddress(config, "$.pool"));
        address asset = vm.parseJsonAddress(config, assetKey);
        uint256 basePool = vm.parseJsonUint(config, basePoolKey);

        MockERC20(asset).mint(sender, amt);

        vm.startPrank(sender);
        MockERC20(asset).approve(address(pool), amt);
        uint256 shares = pool.deposit(basePool, amt, sender);
        vm.stopPrank();

        assertEq(pool.getTotalAssets(basePool), amt);
        assertEq(pool.getLiquidityOf(basePool), amt);
        assertEq(pool.getTotalAssets(basePool), amt);
        assertEq(MockERC20(asset).balanceOf(address(sender)), 0);

        vm.prank(sender);
        pool.redeem(basePool, shares, sender, sender);

        assertEq(pool.getTotalAssets(basePool), 0);
        assertEq(pool.getLiquidityOf(basePool), 0);
        assertEq(MockERC20(asset).balanceOf(address(sender)), amt);
    }
}
