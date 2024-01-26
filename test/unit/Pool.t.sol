// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BaseTest} from "./BaseTest.sol";
import {Pool} from "src/Pool.sol";
import {IRateModel} from "src/interfaces/IRateModel.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract PoolTest is BaseTest {
    Pool public pool;
    MintableToken public mockToken;
    MockRateModel public mockRateModel;

    function setUp() public override {
        mockToken = new MintableToken();
        pool = new Pool(address(mockToken), "mock pool", "mp");
        mockRateModel = new MockRateModel();

        // set the position manager to ourselves so we can just mint/burn at will
        pool.setPositionManager(address(this));

        pool.setRateModel(address(mockRateModel));
        super.setUp();
    }

    function testExpectedBorrowSharesMinted(uint256 debt) public {
        // play nicely with the test setup / rounding
        vm.assume(debt% 4 == 0);
        vm.assume(debt < 100000000000000000000000e18);
        vm.assume(debt > 1 gwei);

        /// On the first mint we should have 1:1 shares
        mockToken.mint(address(pool), debt);
        uint256 shares = pool.borrow(address(1), debt);
        assertEq(shares, debt);

        // After a year borrowing the same amount should only give you half the shares
        // becasue the debt per share has doubled
        vm.warp(block.timestamp + 365 days);
        mockToken.mint(address(pool), debt);
        uint256 shares2 = pool.borrow(address(1), debt);
        assertEq(shares2, debt / 2);

        // round up to the nearest share
        assertEq(shares / 2, shares2);

        // After another year borrowing the same amount should only give you half the shares
        // becasue the debt per share has doubled
        vm.warp(block.timestamp + 365 days);
        mockToken.mint(address(pool), debt);
        uint256 shares3 = pool.borrow(address(1), debt);
        assertEq(shares3, debt / 4);
    }

    function testExpectedBorrowSharesBurned(uint256 debt) public {
        vm.assume(debt% 2 == 0);
        vm.assume(debt < 100000000000000000000000e18);
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
        vm.warp(block.timestamp + 365 days);
        // returns debt in shares
        uint256 debtRemaining2 = pool.repay(address(2), debt);
        // shares have doubled in price from 1:1 so we should have half the debt remaining
        // after paying off the oringal debt
        assertEq(debtRemaining2, debt / 2);
    }
}

contract MockRateModel is IRateModel {
    /// Doubles every year
    function rateFactor(uint256 lastUpdated) external view returns (uint256) {
        uint256 secondsInYear = 365 days;
        return (1e18 * (block.timestamp - lastUpdated) / secondsInYear);
    }
}

contract MintableToken is MockERC20 {
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}