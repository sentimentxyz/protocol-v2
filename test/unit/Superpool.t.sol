// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Errors} from "src/lib/Errors.sol";
import {SuperPool} from "src/SuperPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {TestUtils} from "test/Utils.sol";
import {BaseTest, MintableToken} from "test/unit/BaseTest.sol";
import {FixedRateModel} from "src/FixedRateModel.sol";
import {Pool} from "src/Pool.sol";

contract SuperPoolTest is BaseTest {
    SuperPool superPool;
    MintableToken mockToken;

    function setUp() public override {
        super.setUp();

        mockToken = new MintableToken();
        superPool = new SuperPool();
        superPool = SuperPool(address(TestUtils.makeProxy(address(superPool), address(this))));
        superPool.initialize(address(mockToken), "SuperPool", "SP");
    }

    function testZereodPoolsAreRemoved() public {
        address pool1 = _setDefaultPoolCap();
        address pool2 = _setDefaultPoolCap();
        address pool3 = _setDefaultPoolCap();

        _setPoolCap(pool2, 0);

        address[] memory pools = superPool.pools();

        assertEq(superPool.poolCap(pool2), 0);
        assertEq(address(pools[1]), address(pool3));
        assertEq(address(pools[0]), address(pool1));
        assertEq(superPool.pools().length, 2);
    }

    function testRemoveAllPools() public {
        address pool1 = _setDefaultPoolCap();
        address pool2 = _setDefaultPoolCap();
        address pool3 = _setDefaultPoolCap();

        assertEq(superPool.pools().length, 3);

        _setPoolCap(pool1, 0);
        _setPoolCap(pool2, 0);
        _setPoolCap(pool3, 0);

        assertEq(superPool.pools().length, 0);
    }

    function testPoolCapAdjusted() public {
        address pool1 = _setDefaultPoolCap();
        assertEq(superPool.poolCap(pool1), 100);
        assertEq(superPool.totalPoolCap(), 100);
        address pool2 = _setDefaultPoolCap();
        assertEq(superPool.poolCap(pool2), 101);
        assertEq(superPool.totalPoolCap(), 201);

        _setPoolCap(pool1, 0);

        assertEq(superPool.poolCap(pool1), 0);
        assertEq(superPool.totalPoolCap(), 101);
    }

    function testDepositsWork(uint256 amount) public {
        vm.assume(amount < BIG_NUMBER);

        _setPoolCap(_deployMockPool(), type(uint256).max);

        mockToken.mint(address(this), amount);
        mockToken.approve(address(superPool), amount);
        superPool.deposit(amount, address(this));
        assertEq(superPool.balanceOf(address(this)), amount);
    }

    function testWithdrawsWork(uint256 amount) public {
        vm.assume(amount < BIG_NUMBER);

        _setPoolCap(_deployMockPool(), type(uint256).max);

        mockToken.mint(address(this), amount);
        mockToken.approve(address(superPool), amount);

        uint256 startingAmount = mockToken.balanceOf(address(this));
        superPool.deposit(amount, address(this));
        assertEq(superPool.balanceOf(address(this)), amount);

        superPool.withdraw(amount, address(this), address(this));
        assertEq(superPool.balanceOf(address(this)), 0);
        assertEq(mockToken.balanceOf(address(this)), startingAmount);
    }

    function testRedeemsWork(uint256 amount) public {
        vm.assume(amount < BIG_NUMBER);
        vm.assume(amount > 10);

        _setPoolCap(_deployMockPool(), type(uint256).max);

        mockToken.mint(address(this), amount);
        mockToken.approve(address(superPool), amount);

        uint256 startingAmount = mockToken.balanceOf(address(this));
        superPool.deposit(amount, address(this));
        assertEq(superPool.balanceOf(address(this)), amount);

        superPool.redeem(amount, address(this), address(this));
        assertEq(superPool.balanceOf(address(this)), 0);
        assertEq(mockToken.balanceOf(address(this)), startingAmount);
    }

    function testAllocateToPool() public {
        address pool = address(TestUtils.deployPool(address(this), address(this), address(mockToken)));
        address rateModel = address(new FixedRateModel(1e18));
        Pool(pool).setRateModel(rateModel);

        mockToken.mint(address(this), 10e18);
        mockToken.approve(address(superPool), 10e18);
        superPool.setPoolCap(pool, 10e18);
        superPool.deposit(10e18, address(this));

        assertEq(mockToken.balanceOf(address(superPool)), 10e18);

        superPool.poolDeposit(pool, 10e18);

        assertEq(mockToken.balanceOf(pool), 10e18);
    }

    function testRemoveAllocationFromPool() public {
        address pool = address(TestUtils.deployPool(address(this), address(this), address(mockToken)));
        address rateModel = address(new FixedRateModel(1e18));
        Pool(pool).setRateModel(rateModel);

        mockToken.mint(address(this), 10e18);
        mockToken.approve(address(superPool), 10e18);
        superPool.setPoolCap(pool, 10e18);
        superPool.deposit(10e18, address(this));

        superPool.poolDeposit(pool, 10e18);

        assertEq(mockToken.balanceOf(pool), 10e18);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10e18;

        superPool.withdrawWithPath(10e18, amounts);

        assertEq(mockToken.balanceOf(pool), 0);
    }

    function testWithdrawMultiplePools() public {}

    function testSetPoolCapOnlyOwner(address notOwner) public {
        vm.assume(notOwner != address(this));

        address pool = address(TestUtils.deployPool(address(this), address(this), address(mockToken)));

        vm.startPrank(notOwner);

        vm.expectRevert();
        superPool.setPoolCap(pool, 1e18);

        vm.stopPrank();
    }

    function testPoolDepositOnlyOwner(address notOwner) public {
        vm.assume(notOwner != address(this));

        address pool = address(TestUtils.deployPool(address(this), address(this), address(mockToken)));

        vm.startPrank(notOwner);

        vm.expectRevert(Errors.OnlyAllocatorOrOwner.selector);
        superPool.poolDeposit(pool, 1e18);

        vm.stopPrank();
    }

    function testPoolWithdrawOnlyOwner(address notOwner) public {
        vm.assume(notOwner != address(this));

        address pool = address(TestUtils.deployPool(address(this), address(this), address(mockToken)));

        vm.startPrank(notOwner);

        vm.expectRevert();
        superPool.poolWithdraw(pool, 1e18);

        vm.stopPrank();
    }

    function testSetAllocatorOnlyOwner(address notOwner) public {
        vm.assume(notOwner != address(this));

        address pool = address(TestUtils.deployPool(address(this), address(this), address(mockToken)));

        vm.startPrank(notOwner);

        vm.expectRevert();
        superPool.setAllocator(address(1));

        vm.stopPrank();
    }

    function _setDefaultPoolCap() public returns (address) {
        uint256 len = superPool.pools().length;
        address pool = _deployMockPool();

        superPool.setPoolCap(pool, 100 + len);

        return pool;
    }

    function _setPoolCap(address pool, uint256 cap) public {
        superPool.setPoolCap(address(pool), cap);
    }

    function _deployMockPool() public returns (address) {
        return address(new MockPool(address(mockToken)));
    }
}

contract MockPool {
    address public immutable asset;

    constructor(address _asset) {
        asset = _asset;
    }

    function balanceOf(address) external returns (uint256) {
        return 0;
    }

    function previewRedeem(uint256 amt) external returns (uint256) {
        return amt;
    }
}
