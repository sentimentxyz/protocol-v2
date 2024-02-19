// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest, MintableToken} from "./BaseTest.sol";
import {Pool} from "src/Pool.sol";
import {IRateModel} from "src/interfaces/IRateModel.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {TestUtils} from "test/Utils.sol";
import {FixedRateModel} from "src/irm/FixedRateModel.sol";

contract PoolTest is BaseTest {
    Pool public pool;
    MintableToken public mockToken;
    FixedRateModel public rateModel;

    function setUp() public override {
        mockToken = new MintableToken();
        // set ourselves as the pos manager so we can mint/burn at will
        pool = new Pool(address(this));
        pool = Pool(payable(address(TestUtils.makeProxy(address(pool), address(this)))));
        pool.initialize(address(mockToken), "test", "test");

        rateModel = new FixedRateModel(1e18);

        pool.setRateModel(address(rateModel));
        pool.setPoolCap(type(uint256).max);
        super.setUp();
    }

    function testExpectedBorrowSharesMinted(uint256 debt) public {
        // play nicely with the test setup / rounding
        vm.assume(debt % 4 == 0);
        vm.assume(debt < BIG_NUMBER);
        vm.assume(debt > 0);

        /// On the first mint we should have 1:1 shares
        mockToken.mint(address(pool), debt);
        uint256 shares = pool.borrow(address(1), debt);
        assertEq(shares, debt);

        // After a year borrowing the same amount should only give you half the shares
        // becasue the debt per share has doubled
        vm.warp(block.timestamp + 365.25 days);
        mockToken.mint(address(pool), debt);
        uint256 shares2 = pool.borrow(address(1), debt);
        assertEq(shares2, debt / 2);

        // round up to the nearest share
        assertEq(shares / 2, shares2);

        // After another year borrowing the same amount should only give you half the shares
        // becasue the debt per share has doubled
        vm.warp(block.timestamp + 365.25 days);
        mockToken.mint(address(pool), debt);
        uint256 shares3 = pool.borrow(address(1), debt);
        assertEq(shares3, debt / 4);
    }

    function testExpectedBorrowSharesBurned(uint256 debt) public {
        vm.assume(debt % 2 == 0);
        vm.assume(debt < BIG_NUMBER);
        vm.assume(debt > 0);

        /// On the first mint we should have 1:1 shares
        mockToken.mint(address(pool), debt);
        uint256 shares = pool.borrow(address(1), debt);
        assertEq(shares, debt);

        // at first it should be 1:1 one repaying debt
        uint256 debtRemaining = pool.repay(address(1), debt / 2);
        assertEq(debtRemaining, debt / 2);

        mockToken.mint(address(pool), debt);
        uint256 shares2 = pool.borrow(address(2), debt);
        assertEq(shares2, debt);

        // after 1 year the debt per share should have doubled
        vm.warp(block.timestamp + 365.25 days);
        // returns debt in shares
        uint256 debtRemaining2 = pool.repay(address(2), debt);
        // shares have doubled in price from 1:1 so we should have half the debt remaining
        // after paying off the oringal debt
        assertEq(debtRemaining2, debt / 2);
    }

    function testDepositsWork(uint256 amount) public {
        vm.assume(amount < BIG_NUMBER);
        mockToken.mint(address(this), amount);
        mockToken.approve(address(pool), amount);
        pool.deposit(amount, address(this));
        assertEq(pool.balanceOf(address(this)), amount);
    }

    function testWithdrawsWork(uint256 amount) public {
        vm.assume(amount < BIG_NUMBER);
        mockToken.mint(address(this), amount);
        mockToken.approve(address(pool), amount);

        uint256 startingAmount = mockToken.balanceOf(address(this));
        pool.deposit(amount, address(this));
        assertEq(pool.balanceOf(address(this)), amount);

        pool.withdraw(amount, address(this), address(this));
        assertEq(pool.balanceOf(address(this)), 0);
        assertEq(mockToken.balanceOf(address(this)), startingAmount);
    }

    function testRedeemsWork(uint256 amount) public {
        vm.assume(amount < BIG_NUMBER);
        mockToken.mint(address(this), amount);
        mockToken.approve(address(pool), amount);

        uint256 startingAmount = mockToken.balanceOf(address(this));
        pool.deposit(amount, address(this));
        assertEq(pool.balanceOf(address(this)), amount);

        pool.redeem(amount, address(this), address(this));
        assertEq(pool.balanceOf(address(this)), 0);
        assertEq(mockToken.balanceOf(address(this)), startingAmount);
    }

    function testCantWithdrawIfTooManyBorrows() public {
        uint256 depositAmount = 20e18;

        mockToken.mint(address(this), depositAmount);
        mockToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount, address(this));

        uint256 borrowAmount = 10e18;
        pool.borrow(address(1), borrowAmount);

        // should fail because we have too many borrows
        vm.expectRevert("ERC20: subtraction underflow");
        pool.withdraw(depositAmount, address(this), address(this));

        pool.repay(address(1), borrowAmount);
        // we actullay need to transfer the funds back seperately since were acting as a privledged role above
        vm.prank(address(1));
        mockToken.transfer(address(pool), borrowAmount);

        // should succeed now that we have repaid
        pool.withdraw(depositAmount, address(this), address(this));
    }

    function testCantRedeemIfTooManyBorrows() public {
        uint256 depositAmount = 20e18;

        mockToken.mint(address(this), depositAmount);
        mockToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount, address(this));

        uint256 borrowAmount = 10e18;
        pool.borrow(address(1), borrowAmount);

        // should fail because we have too many borrows
        vm.expectRevert("ERC20: subtraction underflow");
        pool.redeem(depositAmount, address(this), address(this));

        pool.repay(address(1), borrowAmount);
        // we actullay need to transfer the funds back seperately since were acting as a privledged role above
        vm.prank(address(1));
        mockToken.transfer(address(pool), borrowAmount);

        // should succeed now that we have repaid
        pool.redeem(depositAmount, address(this), address(this));
    }

    function testSetRateModelOnlyOwner(address tryMe) public {
        vm.assume(tryMe != address(this));

        vm.startPrank(tryMe);

        vm.expectRevert();
        pool.setRateModel(tryMe);

        vm.stopPrank();
    }

    function testFeeOnlyOwner(address tryMe) public {
        vm.assume(tryMe != address(this));

        vm.startPrank(tryMe);

        vm.expectRevert();
        pool.setOriginationFee(1);

        vm.stopPrank();
    }
}
