// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import { SuperPool } from "src/SuperPool.sol";

contract HlSuperPoolTest is Test {
    address immutable GUY = makeAddr("GUY");
    IERC20 constant borrowAsset = IERC20(0x5555555555555555555555555555555555555555);
    SuperPool constant SUPERPOOL = SuperPool(0x2831775cb5e64B1D892853893858A261E898FbEb);

    function testSuperPoolDeposit(uint256 amt) public {
        assert(GUY != address(0));
        vm.assume(amt > 0 && amt < 699_999e18);
        uint256 shares = _deposit(amt);
        assertEq(SUPERPOOL.balanceOf(GUY), shares);
    }

    function testSuperPoolWithdraw(uint256 amt) public {
        assert(GUY != address(0));
        vm.assume(amt > 0 && amt < 699_999e18);
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
