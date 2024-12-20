// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { SuperPool } from "src/SuperPool.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract HlSuperPoolTest is Test {
    address immutable GUY = makeAddr("GUY");
    MockERC20 constant USDC = MockERC20(0x3e8aAB9Aad036f37bFC52B9Ae0B99AE1CB0C3959);
    SuperPool constant SUPERPOOL = SuperPool(0x8F1dCB9394025c61F34cA76b42b047c29f92c7c2);

    function testSuperPoolDeposit(uint256 amt) public {
        assert(GUY != address(0));
        vm.assume(amt > 0 && amt < 5e33);
        uint256 shares = _deposit(amt);
        assertEq(SUPERPOOL.balanceOf(GUY), shares);
    }

    function testSuperPoolWithdraw(uint256 amt) public {
        assert(GUY != address(0));
        vm.assume(amt > 0 && amt < 5e33);
        _deposit(amt);
        vm.startPrank(GUY);
        uint256 assets = SUPERPOOL.withdraw(amt, GUY, GUY);
        vm.stopPrank();
        assertEq(USDC.balanceOf(GUY), assets);
    }

    function _deposit(uint256 amt) internal returns (uint256 shares) {
        USDC.mint(GUY, amt);
        vm.startPrank(GUY);
        USDC.approve(address(SUPERPOOL), amt);
        shares = SUPERPOOL.deposit(amt, GUY);
        vm.stopPrank();
    }
}
