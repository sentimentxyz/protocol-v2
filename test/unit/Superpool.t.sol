// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
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

    function testWithdrawFailIfNoFunds() public {
        vm.expectRevert();
        superPool.withdraw(100, address(this), address(this));
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

    function testIncreasePoolCap() public {
        address pool = _deployMockPool();
        _setPoolCap(pool, 100);

        assertEq(superPool.poolCap(pool), 100);

        superPool.setPoolCap(pool, 200);

        assertEq(superPool.poolCap(pool), 200);

        superPool.setPoolCap(pool, 300);

        assertEq(superPool.poolCap(pool), 300);
    }

    function testMultipleDepositersCanWithdrawFully() public {
        _setPoolCap(_deployMockPool(), type(uint256).max);

        address a = address(1);
        address b = address(2);
        mockToken.mint(a, 100);
        mockToken.mint(b, 100);

        vm.startPrank(a);
        
        mockToken.approve(address(superPool), 100);
        superPool.deposit(100, a);

        vm.stopPrank();
        vm.startPrank(b);
         mockToken.approve(address(superPool), 100);
        superPool.deposit(100, b);

        vm.stopPrank();

        assertEq(superPool.balanceOf(a), 100);
        assertEq(superPool.balanceOf(b), 100);

        vm.prank(a);
        superPool.withdraw(100, a, a);

        vm.prank(b);
        superPool.withdraw(100, b, b);

        assertEq(superPool.balanceOf(a), 0);
        assertEq(superPool.balanceOf(b), 0);
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

    function testWithdrawWithPath() public {
        Pool poolA = TestUtils.deployPool(address(this), address(this), address(mockToken));
        Pool poolB = TestUtils.deployPool(address(this), address(this), address(mockToken));

        FixedRateModel rateModel = new FixedRateModel(1e18);

        poolA.setRateModel(address(rateModel));
        poolB.setRateModel(address(rateModel));

        _setPoolCap(address(poolA), 10e18);
        _setPoolCap(address(poolB), 10e18);

        mockToken.mint(address(this), 10e18);
        mockToken.approve(address(superPool), 10e18);
        superPool.deposit(10e18, address(this));

        superPool.poolDeposit(address(poolA), 5e18);
        superPool.poolDeposit(address(poolB), 5e18);

        assertEq(mockToken.balanceOf(address(poolA)), 5e18);
        assertEq(mockToken.balanceOf(address(poolB)), 5e18);

        vm.expectRevert();
        superPool.withdrawWithPath(10e18, new uint256[](0));

        vm.expectRevert();
        superPool.withdraw(10e18, address(this), address(this));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5e18;
        amounts[1] = 5e18;

        superPool.withdrawWithPath(10e18, amounts);

        assertEq(mockToken.balanceOf(address(poolA)), 0);
        assertEq(mockToken.balanceOf(address(poolB)), 0);
    }

    function testWithdrawWithPartialFromPath() public {
        Pool poolA = TestUtils.deployPool(address(this), address(this), address(mockToken));

        FixedRateModel rateModel = new FixedRateModel(1e18);

        poolA.setRateModel(address(rateModel));

        _setPoolCap(address(poolA), 10e18);

        mockToken.mint(address(this), 10e18);
        mockToken.approve(address(superPool), 10e18);
        superPool.deposit(10e18, address(this));

        superPool.poolDeposit(address(poolA), 5e18);

        assertEq(mockToken.balanceOf(address(poolA)), 5e18);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2e18;

        superPool.withdrawWithPath(7e18, amounts);
    }

    function testWithdrawFailsIfAssetsLent() public {
        Pool pool = TestUtils.deployPool(address(this), address(this), address(mockToken));

        FixedRateModel rateModel = new FixedRateModel(1e18);

        pool.setRateModel(address(rateModel));

        _setPoolCap(address(pool), 10e18);

        mockToken.mint(address(this), 10e18);
        mockToken.approve(address(superPool), 10e18);
        superPool.deposit(10e18, address(this));

        superPool.poolDeposit(address(pool), 5e18);

        assertEq(mockToken.balanceOf(address(pool)), 5e18);

        pool.borrow(address(this), 5e18);

        vm.expectRevert();
        superPool.withdraw(10e18, address(this), address(this));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5e18;

        vm.expectRevert();
        superPool.withdrawWithPath(10e18, amounts);
    }

    function testFeeAccruedRedeem() public {}

    function testFeeAccruedWithdraw() public {}

    function testCantMintMoreThanCap() public {
        address pool = _deployMockPool();
        _setPoolCap(pool, 100);

        mockToken.mint(address(this), 101);
        mockToken.approve(address(superPool), 101);

        vm.expectRevert();
        superPool.mint(101, address(this));

        superPool.mint(100, address(this));
    }

    function testCantDepositMoreThanCap() public {
       address pool = _deployMockPool();
        _setPoolCap(pool, 100);

        mockToken.mint(address(this), 101);
        mockToken.approve(address(superPool), 101);

        vm.expectRevert();
        superPool.deposit(101, address(this));

        superPool.deposit(100, address(this));
    }


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

        vm.expectRevert(SuperPool.OnlyAllocatorOrOwner.selector);
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
