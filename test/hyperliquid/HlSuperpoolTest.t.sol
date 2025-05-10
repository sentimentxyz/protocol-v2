// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import { SuperPool } from "src/SuperPool.sol";

contract HlSuperPoolTest is Test {
    address immutable GUY = makeAddr("GUY");
    IERC20 constant borrowAsset = IERC20(0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb);
    SuperPool constant SUPERPOOL = SuperPool(0x34B2B0DE7d288e79bbcfCEe6C2a222dAe25fF88D);

    function testSuperPoolDeposit(uint256 amt) public {
        assert(GUY != address(0));
        vm.assume(amt > 0 && amt < 900_000e6);
        uint256 shares = _deposit(amt);
        assertEq(SUPERPOOL.balanceOf(GUY), shares);
    }

    function testSuperPoolWithdraw(uint256 amt) public {
        assert(GUY != address(0));
        vm.assume(amt > 0 && amt < 900_000e6);
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
