// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { SuperPool } from "src/SuperPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HlSuperPoolTest is Test {
    address immutable GUY = makeAddr("GUY");
    IERC20 constant borrowAsset = IERC20(0x5555555555555555555555555555555555555555);
    SuperPool constant SUPERPOOL = SuperPool(0x17D9bA6c4276A5A679221B7128Ad3301d2b857B1);

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
        assertEq(borrowAsset.balanceOf(GUY), assets);
    }

    function _deposit(uint256 amt) internal returns (uint256 shares) {
        deal(address(borrowAsset), GUY, amt);
        vm.startPrank(GUY);
        borrowAsset.approve(address(SUPERPOOL), amt);
        shares = SUPERPOOL.deposit(amt, GUY);
        vm.stopPrank();
    }
}
