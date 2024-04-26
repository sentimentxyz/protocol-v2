// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest, MintableToken} from "./BaseTest.t.sol";
import {Pool} from "src/Pool.sol";
import {IRateModel} from "src/interface/IRateModel.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {TestUtils} from "test/TestUtils.sol";
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
        rateModel = new FixedRateModel(1e18);

        pool.initialize(address(mockToken), address(rateModel), type(uint256).max, uint256(0), "test", "test");
        super.setUp();
    }

    function testDepositsWork(uint256 amount) public {
        vm.assume(amount > 0 && amount < MAX_NUM);
        mockToken.mint(address(this), amount);
        mockToken.approve(address(pool), amount);
        pool.deposit(amount, address(this));
        assertEq(pool.balanceOf(address(this)), amount);
    }

    function testWithdrawsWork(uint256 amount) public {
        vm.assume(amount > 0 && amount < MAX_NUM);
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
        vm.assume(amount > 0 && amount < MAX_NUM);
        mockToken.mint(address(this), amount);
        mockToken.approve(address(pool), amount);

        uint256 startingAmount = mockToken.balanceOf(address(this));
        pool.deposit(amount, address(this));
        assertEq(pool.balanceOf(address(this)), amount);

        pool.redeem(amount, address(this), address(this));
        assertEq(pool.balanceOf(address(this)), 0);
        assertEq(mockToken.balanceOf(address(this)), startingAmount);
    }

    function testBorrowFailsIfTooMuchDebt() public {
        uint256 depositAmount = 20e18;

        mockToken.mint(address(this), depositAmount);
        mockToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount, address(this));

        // should fail because we have too much debt
        vm.expectRevert();
        pool.borrow(address(1), depositAmount + 1);
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
        pool.requestRateModelUpdate(tryMe);

        vm.stopPrank();
    }

    function testFeeOnlyOwner(address tryMe) public {
        vm.assume(tryMe != address(this));

        vm.startPrank(tryMe);

        vm.expectRevert();
        pool.setOriginationFee(1);

        vm.stopPrank();
    }

    function testOriginationFeeWorks() public {
        uint256 depositAmount = 10e18;

        mockToken.mint(address(this), depositAmount);
        mockToken.approve(address(pool), depositAmount);

        // Half
        pool.setOriginationFee(5e17);
        // send fee to address 1
        pool.transferOwnership(address(1));

        pool.deposit(depositAmount, address(this));
        assertEq(mockToken.balanceOf(address(this)), 0);
        assertEq(mockToken.balanceOf(address(pool)), depositAmount);

        pool.borrow(address(this), depositAmount);
        assertEq(mockToken.balanceOf(address(this)), depositAmount / 2);
        assertEq(mockToken.balanceOf(address(1)), depositAmount / 2);
    }

    /// Test Intrest Accrual On Borrower side

    function testExpectedBorrowSharesMinted(uint256 debt) public {
        // play nicely with the test setup / rounding
        vm.assume(debt % 4 == 0);
        vm.assume(debt < MAX_NUM);
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
        vm.assume(debt < MAX_NUM);
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

    /// Test Intrest Accrual On lender side

    function testInterestAccruedDeposit() public {
        uint256 depositAmount1 = 10e18;
        uint256 depositAmount2 = 10e18;

        mockToken.mint(address(this), depositAmount1 + depositAmount2);
        mockToken.approve(address(pool), depositAmount1 + depositAmount2);

        pool.deposit(depositAmount1, address(this));

        // borrow so interest is accrued
        pool.borrow(address(1), depositAmount1);

        uint256 first = pool.totalBorrows();

        vm.warp(block.timestamp + 365.25 days);

        pool.deposit(depositAmount2, address(this));

        uint256 second = pool.totalBorrows();

        assertEq(first, second / 2);
    }

    function testInterestAccruedWithdraw() public {
        uint256 depositAmount = 10e18;

        mockToken.mint(address(this), depositAmount);
        mockToken.approve(address(pool), depositAmount);

        pool.deposit(depositAmount, address(this));

        // borrow so interest is accrued
        pool.borrow(address(1), depositAmount / 2);

        uint256 first = pool.totalBorrows();

        vm.warp(block.timestamp + 365.25 days);

        pool.withdraw(depositAmount / 2, address(this), address(this));

        uint256 second = pool.totalBorrows();

        assertEq(first, second / 2);
    }

    function testInterestAccruedMint() public {
        uint256 depositAmount = 10e18;
        uint256 mintAmount = 10e18;

        mockToken.mint(address(this), depositAmount);
        mockToken.approve(address(pool), depositAmount);

        pool.deposit(depositAmount, address(this));

        // borrow so interest is accrued
        pool.borrow(address(1), depositAmount / 2);

        uint256 first = pool.totalBorrows();

        vm.warp(block.timestamp + 365.25 days);

        uint256 assetsNeeded = pool.previewMint(mintAmount);
        mockToken.mint(address(this), assetsNeeded);
        mockToken.approve(address(pool), assetsNeeded);

        pool.mint(mintAmount, address(this));

        uint256 second = pool.totalBorrows();

        assertEq(first, second / 2);
    }

    function testInterestAccruedRedeem() public {
        uint256 depositAmount = 10e18;

        mockToken.mint(address(this), depositAmount);
        mockToken.approve(address(pool), depositAmount);

        pool.deposit(depositAmount, address(this));

        // borrow so interest is accrued
        pool.borrow(address(1), depositAmount / 2);

        uint256 first = pool.totalBorrows();

        vm.warp(block.timestamp + 365.25 days);

        uint256 sharesNeeded = pool.convertToShares(depositAmount / 2);

        pool.redeem(sharesNeeded, address(this), address(this));

        uint256 second = pool.totalBorrows();

        assertEq(first, second / 2);
    }
}
