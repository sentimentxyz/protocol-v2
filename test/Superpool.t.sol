// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Errors} from "src/lib/Errors.sol";
import {SuperPool} from "src/SuperPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {TestUtils} from "test/TestUtils.sol";
import {BaseTest, MintableToken} from "./BaseTest.t.sol";
import {FixedRateModel} from "src/irm/FixedRateModel.sol";
import {Pool} from "src/Pool.sol";

contract SuperPoolTest is BaseTest {
    SuperPool superPool;
    MintableToken mockToken;

    function setUp() public override {
        super.setUp();

        mockToken = new MintableToken();
        superPool = new SuperPool();
        superPool = SuperPool(address(TestUtils.makeProxy(address(superPool), address(this))));
        superPool.initialize(address(mockToken), type(uint256).max, uint256(0), address(0), "SuperPool", "SP");
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
        // set all the pools to default cap
        address pool1 = _setDefaultPoolCap();
        address pool2 = _setDefaultPoolCap();
        address pool3 = _setDefaultPoolCap();

        // we should have 3 pools
        assertEq(superPool.pools().length, 3);

        // set them all to 0
        _setPoolCap(pool1, 0);
        _setPoolCap(pool2, 0);
        _setPoolCap(pool3, 0);

        assertEq(superPool.pools().length, 0);
    }

    function testPoolCapAdjusted() public {
        // set the default pool cap
        address pool1 = _setDefaultPoolCap();
        assertEq(superPool.poolCap(pool1), 100);

        // set the default pool cap for another pool
        address pool2 = _setDefaultPoolCap();
        assertEq(superPool.poolCap(pool2), 101);

        // zero out the first pool
        _setPoolCap(pool1, 0);

        assertEq(superPool.poolCap(pool1), 0);
    }

    function testIncreasePoolCap() public {
        address pool = _deployMockPool();
        _setPoolCap(pool, 100);

        // chheck the original pool cap
        assertEq(superPool.poolCap(pool), 100);

        // set it to 200
        superPool.setPoolCap(pool, 200);

        assertEq(superPool.poolCap(pool), 200);

        // set it to 300
        superPool.setPoolCap(pool, 300);

        assertEq(superPool.poolCap(pool), 300);
    }

    function testMultipleDepositersCanWithdrawFully() public {
        _setPoolCap(_deployMockPool(), type(uint256).max);

        // mint 100 tokens to two different addresses
        address a = address(1);
        address b = address(2);
        mockToken.mint(a, 100);
        mockToken.mint(b, 100);

        // deposit all tokens from address a and b
        vm.startPrank(a);

        mockToken.approve(address(superPool), 100);
        superPool.deposit(100, a);

        vm.stopPrank();

        vm.startPrank(b);

        mockToken.approve(address(superPool), 100);
        superPool.deposit(100, b);

        vm.stopPrank();

        // check balances
        assertEq(superPool.balanceOf(a), 100);
        assertEq(superPool.balanceOf(b), 100);

        // we should be able to fully withdraw
        vm.prank(a);
        superPool.withdraw(100, a, a);

        vm.prank(b);
        superPool.withdraw(100, b, b);

        // both addresses should have no shares in the super pool
        assertEq(superPool.balanceOf(a), 0);
        assertEq(superPool.balanceOf(b), 0);
    }

    function testDepositsWork(uint256 amount) public {
        vm.assume(amount < MAX_NUM);

        _setPoolCap(_deployMockPool(), type(uint256).max);

        mockToken.mint(address(this), amount);
        mockToken.approve(address(superPool), amount);
        superPool.deposit(amount, address(this));
        assertEq(superPool.balanceOf(address(this)), amount);
    }

    function testWithdrawsWork(uint256 amount) public {
        vm.assume(amount < MAX_NUM);

        // set the pool cap to the max
        _setPoolCap(_deployMockPool(), type(uint256).max);
        mockToken.mint(address(this), amount);
        mockToken.approve(address(superPool), amount);

        // we should be able to deposit
        uint256 startingAmount = mockToken.balanceOf(address(this));
        superPool.deposit(amount, address(this));
        assertEq(superPool.balanceOf(address(this)), amount);

        // no change in exchange rate so just withdraw everything
        superPool.withdraw(amount, address(this), address(this));
        assertEq(superPool.balanceOf(address(this)), 0);
        assertEq(mockToken.balanceOf(address(this)), startingAmount);
    }

    function testRedeemsWork(uint256 amount) public {
        vm.assume(amount < MAX_NUM);
        vm.assume(amount > 10);

        // setup pool
        _setPoolCap(_deployMockPool(), type(uint256).max);
        mockToken.mint(address(this), amount);
        mockToken.approve(address(superPool), amount);

        // we should be able to deposit
        uint256 startingAmount = mockToken.balanceOf(address(this));
        superPool.deposit(amount, address(this));
        assertEq(superPool.balanceOf(address(this)), amount);

        // no change in exchange rate so just redeem everything
        superPool.redeem(amount, address(this), address(this));
        assertEq(superPool.balanceOf(address(this)), 0);
        assertEq(mockToken.balanceOf(address(this)), startingAmount);
    }

    function testAllocateToPool() public {
        uint256 depositAmount = 10e18;

        // deploy pool and set rate model
        address rateModel = address(new FixedRateModel(1e18));
        address pool = address(TestUtils.deployPool(address(this), address(this), address(mockToken), rateModel));

        // mint and deposit tokens
        mockToken.mint(address(this), depositAmount);
        mockToken.approve(address(superPool), depositAmount);
        superPool.setPoolCap(pool, depositAmount);
        superPool.deposit(depositAmount, address(this));

        // we hsould have deposted this amount into the super pool
        assertEq(mockToken.balanceOf(address(superPool)), depositAmount);

        // allocate to the pool
        superPool.poolDeposit(pool, depositAmount);

        // we should have deposited this amount into the pool
        assertEq(mockToken.balanceOf(pool), depositAmount);
    }

    function testRemoveAllocationFromPool() public {
        uint256 depositAmount = 10e18;

        // deploy pool and set rate model
        address rateModel = address(new FixedRateModel(1e18));
        address pool = address(TestUtils.deployPool(address(this), address(this), address(mockToken), rateModel));

        // mint and deposit tokens
        mockToken.mint(address(this), depositAmount);
        mockToken.approve(address(superPool), depositAmount);
        superPool.setPoolCap(pool, depositAmount);
        superPool.deposit(depositAmount, address(this));

        // allocate to pool
        superPool.poolDeposit(pool, depositAmount);

        assertEq(mockToken.balanceOf(pool), depositAmount);

        // remove allocation from pool
        superPool.poolWithdraw(pool, depositAmount);

        // we should have no tokens in the pool
        assertEq(mockToken.balanceOf(pool), 0);
    }

    function testWithdrawWithPath() public {
        uint256 depositAmount = 10e18;
        uint256 poolDepositAmount = depositAmount / 2;

        FixedRateModel rateModel = new FixedRateModel(1e18);

        // deploy two pools
        Pool poolA = TestUtils.deployPool(address(this), address(this), address(mockToken), address(rateModel));
        Pool poolB = TestUtils.deployPool(address(this), address(this), address(mockToken), address(rateModel));

        // set the pool caps for each pool
        _setPoolCap(address(poolA), depositAmount);
        _setPoolCap(address(poolB), depositAmount);

        // deposit tokens into the super pool
        mockToken.mint(address(this), depositAmount);
        mockToken.approve(address(superPool), depositAmount);
        superPool.deposit(depositAmount, address(this));

        // split the deposit between the two pools
        superPool.poolDeposit(address(poolA), poolDepositAmount);
        superPool.poolDeposit(address(poolB), poolDepositAmount);

        assertEq(mockToken.balanceOf(address(poolA)), poolDepositAmount);
        assertEq(mockToken.balanceOf(address(poolB)), poolDepositAmount);

        // at this point we cant withdraw without specificing a path
        vm.expectRevert();
        superPool.withdrawWithPath(depositAmount, new uint256[](0));

        // this should also fail because the balance is not in the super pool
        vm.expectRevert();
        superPool.withdraw(depositAmount, address(this), address(this));

        // request to withdraw 10 tokens from the super pool split among the two pools
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = poolDepositAmount;
        amounts[1] = poolDepositAmount;

        superPool.withdrawWithPath(depositAmount, amounts);

        // pools should  have no more balance
        assertEq(mockToken.balanceOf(address(poolA)), 0);
        assertEq(mockToken.balanceOf(address(poolB)), 0);
    }

    function testWithdrawWithPartialFromPath() public {
        uint256 totalDepositAmount = 10e18;
        uint256 poolDepositAmount = 5e18;
        uint256 withdrawAmount = 7e18;

        assertGt(totalDepositAmount, withdrawAmount);
        assertGt(withdrawAmount, poolDepositAmount);
        assertGt(totalDepositAmount, poolDepositAmount);

        // set up the pool + cap
        FixedRateModel rateModel = new FixedRateModel(1e18);
        Pool poolA = TestUtils.deployPool(address(this), address(this), address(mockToken), address(rateModel));
        _setPoolCap(address(poolA), totalDepositAmount);

        // depoist tokens into pool
        mockToken.mint(address(this), totalDepositAmount);
        mockToken.approve(address(superPool), totalDepositAmount);
        superPool.deposit(totalDepositAmount, address(this));

        // allocate tokens to the pool
        superPool.poolDeposit(address(poolA), poolDepositAmount);

        assertEq(mockToken.balanceOf(address(poolA)), poolDepositAmount);

        // withdraw the diff
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = withdrawAmount - poolDepositAmount;

        superPool.withdrawWithPath(withdrawAmount, amounts);
    }

    function testWithdrawFailsIfAssetsLent() public {
        uint256 depositAmount = 10e18;
        uint256 borrowAmount = 5e18;

        FixedRateModel rateModel = new FixedRateModel(1e18);
        // setup pool
        Pool pool = TestUtils.deployPool(address(this), address(this), address(mockToken), address(rateModel));
        pool.setRateModel(address(rateModel));
        _setPoolCap(address(pool), depositAmount);

        // deposit tokens into the super pool
        mockToken.mint(address(this), depositAmount);
        mockToken.approve(address(superPool), depositAmount);
        superPool.deposit(depositAmount, address(this));

        // allocate to pool
        superPool.poolDeposit(address(pool), borrowAmount);

        assertEq(mockToken.balanceOf(address(pool)), borrowAmount);

        // borrow some amounts
        pool.borrow(address(this), borrowAmount);

        // we should not be able the original amount from the pool since we moved assets to the pool
        vm.expectRevert();
        superPool.withdraw(depositAmount, address(this), address(this));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = borrowAmount;

        // we also shouldnt be able tow withdraw from the pool becuase it has lent its assets
        vm.expectRevert();
        superPool.withdrawWithPath(10e18, amounts);
    }

    function testFeeAccruedRedeem() public {
        address pool = _deployMockPool();
        _setPoolCap(pool, 100);

        superPool.setProtocolFee(5e17);
        superPool.transferOwnership(address(1));

        mockToken.mint(address(this), 100);
        mockToken.approve(address(superPool), 100);
        superPool.deposit(100, address(this));

        superPool.redeem(100, address(this), address(this));

        assertEq(mockToken.balanceOf(address(this)), 50);
        assertEq(mockToken.balanceOf(superPool.owner()), 50);
    }

    function testFeeAccruedWithdraw() public {
        address pool = _deployMockPool();
        _setPoolCap(pool, 100);

        superPool.setProtocolFee(5e17);
        superPool.transferOwnership(address(1));

        mockToken.mint(address(this), 100);
        mockToken.approve(address(superPool), 100);
        superPool.deposit(100, address(this));

        superPool.withdraw(100, address(this), address(this));

        assertEq(mockToken.balanceOf(address(this)), 50);
        assertEq(mockToken.balanceOf(superPool.owner()), 50);
    }

    function testOwnerCanChangeParamsAfterChange() public {
        address pool = _deployMockPool();
        _setPoolCap(pool, 100);

        superPool.setPoolCap(pool, 200);
        assertEq(superPool.poolCap(pool), 200);

        superPool.transferOwnership(address(1));

        vm.expectRevert();
        superPool.setPoolCap(pool, 300);

        vm.prank(address(1));
        superPool.setPoolCap(pool, 300);

        assertEq(superPool.poolCap(pool), 300);
    }

    function testThreeActors() public {
        address a = address(1);
        address b = address(2);
        address c = address(3);

        uint256 amount = 10e18;

        address pool = _deployMockPool();
        _setPoolCap(pool, amount * 3);

        mockToken.mint(a, amount);
        mockToken.mint(b, amount);
        mockToken.mint(c, amount);

        vm.startPrank(a);
        mockToken.approve(address(superPool), amount);
        superPool.deposit(amount, a);
        vm.stopPrank();

        assertEq(superPool.balanceOf(a), amount);

        vm.startPrank(b);
        mockToken.approve(address(superPool), amount);
        superPool.deposit(amount, b);
        vm.stopPrank();

        assertEq(superPool.balanceOf(b), amount);

        vm.startPrank(a);
        superPool.withdraw(amount / 2, a, a);
        vm.stopPrank();

        assertEq(superPool.balanceOf(a), amount / 2);

        vm.startPrank(c);
        mockToken.approve(address(superPool), amount);
        superPool.deposit(amount, c);
        vm.stopPrank();

        assertEq(superPool.balanceOf(c), amount);

        vm.startPrank(a);
        superPool.withdraw(amount / 2, a, a);
        vm.stopPrank();

        assertEq(superPool.balanceOf(a), 0);

        vm.startPrank(b);
        superPool.withdraw(amount, b, b);
        vm.stopPrank();

        assertEq(superPool.balanceOf(b), 0);

        vm.startPrank(c);
        superPool.withdraw(amount, c, c);
        vm.stopPrank();

        assertEq(superPool.balanceOf(c), 0);
    }

    function testCantMintMoreThanCap() public {
        address pool = _deployMockPool();
        _setPoolCap(pool, 100);
        superPool.setTotalPoolCap(100);

        mockToken.mint(address(this), 101);
        mockToken.approve(address(superPool), 101);

        // we shouldnt be able to mint more than the cap
        vm.expectRevert();
        superPool.mint(101, address(this));

        superPool.mint(100, address(this));
    }

    function testCantDepositMoreThanCap() public {
        address pool = _deployMockPool();
        _setPoolCap(pool, 100);
        superPool.setTotalPoolCap(100);

        mockToken.mint(address(this), 101);
        mockToken.approve(address(superPool), 101);

        // we shouldnt be able to deposit more than the cap
        vm.expectRevert();
        superPool.deposit(101, address(this));

        superPool.deposit(100, address(this));
    }

    function testSetPoolCapOnlyOwner(address notOwner) public {
        vm.assume(notOwner != address(this));

        address pool = address(TestUtils.deployPool(address(this), address(this), address(mockToken), address(0)));

        vm.startPrank(notOwner);

        vm.expectRevert();
        superPool.setPoolCap(pool, 1e18);

        vm.stopPrank();
    }

    function testPoolDepositOnlyOwner(address notOwner) public {
        vm.assume(notOwner != address(this) && notOwner != address(mockToken));

        address pool = address(TestUtils.deployPool(address(this), address(this), address(mockToken), address(0)));

        vm.startPrank(notOwner);

        vm.expectRevert(Errors.OnlyAllocatorOrOwner.selector);
        superPool.poolDeposit(pool, 1e18);

        vm.stopPrank();
    }

    function testPoolWithdrawOnlyOwner(address notOwner) public {
        vm.assume(notOwner != address(this));

        address pool = address(TestUtils.deployPool(address(this), address(this), address(mockToken), address(0)));

        vm.startPrank(notOwner);

        vm.expectRevert();
        superPool.poolWithdraw(pool, 1e18);

        vm.stopPrank();
    }

    function testSetAllocatorOnlyOwner(address notOwner) public {
        vm.assume(notOwner != address(this));

        TestUtils.deployPool(address(this), address(this), address(mockToken), address(0));

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

    function testZach_WithdrawAllCanFail() public {
        address pool = _deployMockPool();
        _setPoolCap(pool, 1e18);
        superPool.setProtocolFee(0.75e18);

        // deposit into the superpool
        uint256 deposit = 51;
        mockToken.mint(address(this), deposit);
        mockToken.approve(address(superPool), deposit);
        superPool.deposit(deposit, address(this));

        // simulate interest earned
        uint256 interestAccrued = 50;
        mockToken.mint(address(superPool), interestAccrued);

        // withdraw max will fail due to rounding
        uint256 maxWithdrawal = superPool.maxWithdraw(address(this));
        superPool.withdraw(maxWithdrawal, address(this), address(this));
    }

    function testZachFuzz_WithdrawAllSucceeds(uint256 deposit, uint256 interestAccrued, uint256 fee) public {
        address pool = _deployMockPool();
        _setPoolCap(pool, 1e18);
        fee = bound(fee, 0, 1e18);
        superPool.setProtocolFee(fee);

        // deposit into the superpool
        deposit = bound(deposit, 0, 10e18);
        mockToken.mint(address(this), deposit);
        mockToken.approve(address(superPool), deposit);
        superPool.deposit(deposit, address(this));

        // simulate interest earned
        interestAccrued = bound(interestAccrued, 0, 1e18);
        mockToken.mint(address(superPool), interestAccrued);

        // withdraw max succeeds even with rounding
        uint256 maxWithdrawal = superPool.maxWithdraw(address(this));
        superPool.withdraw(maxWithdrawal, address(this), address(this));
    }
}

contract MockPool {
    address public immutable asset;

    constructor(address _asset) {
        asset = _asset;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function previewRedeem(uint256 amt) external pure returns (uint256) {
        return amt;
    }
}
