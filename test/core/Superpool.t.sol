// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseTest.t.sol";
import { console2 } from "forge-std/console2.sol";

contract SuperPoolUnitTests is BaseTest {
    Pool pool;
    SuperPool superPool;
    SuperPoolFactory superPoolFactory;

    address public feeTo = makeAddr("FeeTo");

    function setUp() public override {
        super.setUp();

        pool = protocol.pool();
        superPoolFactory = protocol.superPoolFactory();

        superPool = SuperPool(
            superPoolFactory.deploySuperPool(
                poolOwner, address(asset1), feeTo, 0.01 ether, 1_000_000 ether, "test", "test"
            )
        );
    }

    function testInitSuperPoolFactory() public {
        superPoolFactory = new SuperPoolFactory(address(pool));
        assertEq(superPoolFactory.POOL(), address(pool));
    }

    function testInitSuperPool() public {
        SuperPool randomPoolRaw =
            new SuperPool(address(pool), address(asset1), feeTo, 0.01 ether, 1_000_000 ether, "test", "test");

        assertEq(address(randomPoolRaw.asset()), address(asset1));
        assertEq(randomPoolRaw.feeRecipient(), feeTo);
        assertEq(randomPoolRaw.fee(), 0.01 ether);
        assertEq(randomPoolRaw.superPoolCap(), 1_000_000 ether);
        assertEq(randomPoolRaw.name(), "test");
        assertEq(randomPoolRaw.symbol(), "test");
    }

    function testDeployAPoolFromFactory() public {
        address feeRecipient = makeAddr("FeeRecipient");

        address deployed =
            superPoolFactory.deploySuperPool(poolOwner, address(asset1), feeRecipient, 0, 0, "test", "test");

        assert(deployed != address(0));
        SuperPool _superPool = SuperPool(deployed);
        assertEq(_superPool.owner(), poolOwner);
        assertEq(address(_superPool.asset()), address(asset1));
        assertEq(_superPool.feeRecipient(), feeRecipient);
        assertEq(_superPool.fee(), 0);
        assertEq(_superPool.superPoolCap(), 0);
        assertEq(_superPool.name(), "test");
        assertEq(_superPool.symbol(), "test");
    }

    function testAddPoolToSuperPool() public {
        vm.startPrank(poolOwner);
        assertEq(superPool.getPoolCount(), 0);
        assertEq(superPool.pools().length, 0);

        superPool.setPoolCap(linearRatePool, 100 ether);

        assertEq(superPool.getPoolCount(), 1);
        assertEq(superPool.pools().length, 1);
        assertEq(superPool.poolCap(linearRatePool), 100 ether);

        vm.expectRevert(); // Cannot mix asset types when initializing pool types
        superPool.setPoolCap(alternateAssetPool, 100 ether);

        for (uint256 i; i < 7; i++) {
            address linearRateModel = address(new LinearRateModel(2e18, 3e18));
            uint256 linearPool =
                pool.initializePool(poolOwner, address(asset1), linearRateModel, 0, 0, type(uint128).max);

            superPool.setPoolCap(linearPool, 50 ether);
        }

        address newLinearModel = address(new LinearRateModel(2e18, 3e18));
        uint256 lastLinearPool =
            pool.initializePool(poolOwner, address(asset1), newLinearModel, 0, 0, type(uint128).max);

        // Test call reverts when adding too many pools
        vm.expectRevert();
        superPool.setPoolCap(lastLinearPool, 50 ether);

        // Call will return if double 0's are passed in
        superPool.setPoolCap(0, 0);
    }

    function testRemovePoolFromSuperPool() public {
        vm.startPrank(poolOwner);
        superPool.setPoolCap(linearRatePool, 100 ether);

        assertEq(superPool.getPoolCount(), 1);
        assertEq(superPool.pools().length, 1);
        assertEq(superPool.poolCap(linearRatePool), 100 ether);

        superPool.setPoolCap(fixedRatePool, 100 ether);

        assertEq(superPool.getPoolCount(), 2);
        assertEq(superPool.pools().length, 2);
        assertEq(superPool.poolCap(fixedRatePool), 100 ether);

        superPool.setPoolCap(linearRatePool2, 100 ether);
        superPool.setPoolCap(fixedRatePool2, 100 ether);

        superPool.setPoolCap(linearRatePool2, 0);

        assertEq(superPool.getPoolCount(), 3);
        assertEq(superPool.pools().length, 3);
        assertEq(superPool.poolCap(linearRatePool2), 0);
    }

    function testCanModifyPoolCap() public {
        vm.startPrank(poolOwner);
        superPool.setPoolCap(linearRatePool, 100 ether);
        assertEq(superPool.poolCap(linearRatePool), 100 ether);

        assertEq(superPool.getPoolCount(), 1);
        assertEq(superPool.pools().length, 1);

        superPool.setPoolCap(linearRatePool, 200 ether);
        assertEq(superPool.poolCap(linearRatePool), 200 ether);

        assertEq(superPool.getPoolCount(), 1);
        assertEq(superPool.pools().length, 1);
    }

    function testNonAdminCannotModifyPoolCaps() public {
        vm.startPrank(user);
        vm.expectRevert();
        superPool.setPoolCap(linearRatePool, 100 ether);
    }

    function testSimpleDepositIntoSuperpool() public {
        vm.startPrank(poolOwner);
        superPool.setPoolCap(linearRatePool, 100 ether);
        vm.stopPrank();

        vm.startPrank(user);

        asset1.mint(user, 100 ether);
        asset1.approve(address(superPool), 100 ether);

        uint256 expectedShares = superPool.previewDeposit(100 ether);
        uint256 shares = superPool.deposit(100 ether, user);
        assertEq(shares, expectedShares);

        assertEq(asset1.balanceOf(address(pool)), 100 ether);
        vm.stopPrank();
    }

    function testZeroShareDeposit() public {
        vm.startPrank(poolOwner);
        superPool.setPoolCap(linearRatePool, 100 ether);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(SuperPool.SuperPool_ZeroShareDeposit.selector, address(superPool), 0));
        superPool.deposit(0, user);
    }

    function testWithdrawalScenarios() public {
        testSimpleDepositIntoSuperpool();
        uint256 shares = superPool.balanceOf(user);
        uint256 assets = superPool.convertToAssets(shares);

        vm.prank(user);
        superPool.approve(user2, shares / 10);

        vm.startPrank(user2);
        superPool.redeem(shares / 10, user2, user);

        vm.expectRevert();
        superPool.withdraw(assets / 10, user2, user);
        vm.stopPrank();

        vm.prank(user);
        superPool.approve(user2, type(uint256).max);

        vm.prank(user2);
        superPool.withdraw(assets / 2, user2, user);

        // coincidenal withdrawal can be covered without dipping into base pools
        asset1.mint(address(superPool), assets / 10);

        vm.prank(user);
        superPool.withdraw(assets / 10, user, user);
    }

    function testWithdrawFromPausedPool() public {
        testSimpleDepositIntoSuperpool();

        vm.startPrank(pool.positionManager());
        pool.borrow(linearRatePool, makeAddr("position"), 100 ether);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(SuperPool.SuperPool_NotEnoughLiquidity.selector, address(superPool)));
        superPool.withdraw(10 ether, user, user);
    }

    function testTotalAssets(uint96 amount) public {
        vm.assume(amount > 1e6);

        vm.startPrank(poolOwner);
        superPool.setPoolCap(linearRatePool, amount);
        superPool.setPoolCap(fixedRatePool, amount);
        vm.stopPrank();

        vm.startPrank(user);
        asset1.mint(user, amount);
        asset1.approve(address(superPool), amount);
        superPool.deposit(amount, user);
        vm.stopPrank();

        assertEq(superPool.totalAssets(), amount);
    }

    function testSimpleDepositIntoMultiplePools() public {
        vm.startPrank(poolOwner);
        superPool.setPoolCap(linearRatePool, 100 ether);
        superPool.setPoolCap(fixedRatePool, 100 ether);
        vm.stopPrank();

        vm.startPrank(user);

        asset1.mint(user, 200 ether);
        asset1.approve(address(superPool), 200 ether);

        uint256 expectedShares = superPool.previewDeposit(200 ether);
        uint256 shares = superPool.deposit(200 ether, user);

        assertEq(shares, expectedShares);
        assertEq(asset1.balanceOf(address(pool)), 200 ether);
    }

    function testDepositMoreThanPoolCap() public {
        vm.startPrank(poolOwner);
        superPool.setPoolCap(linearRatePool, 50 ether);
        vm.stopPrank();

        vm.startPrank(user);
        asset1.mint(user, 100 ether);
        asset1.approve(address(superPool), 100 ether);

        superPool.deposit(100 ether, user);
        assertEq(asset1.balanceOf(address(superPool)), 50 ether);
    }

    function testPartialWithdrawal(uint96 amt) public {
        vm.assume(amt > 1e6);
        vm.startPrank(poolOwner);
        superPool.setPoolCap(linearRatePool, amt / 2);
        superPool.setPoolCap(fixedRatePool, (amt / 2) + 1);
        vm.stopPrank();

        vm.startPrank(user);

        asset1.mint(user, amt);
        asset1.approve(address(superPool), amt);

        uint256 totalShares = superPool.deposit(amt, user);

        uint256 expectedAssets = superPool.previewRedeem(totalShares / 2);
        uint256 assets = superPool.redeem(totalShares / 2, user, user);
        assertEq(assets, expectedAssets);
        assertEq(asset1.balanceOf(user), amt / 2);

        uint256 expectedShares = superPool.previewWithdraw(amt / 2);
        uint256 shares = superPool.withdraw(amt / 2, user, user);
        assertEq(shares, expectedShares);
        assertApproxEqAbs(asset1.balanceOf(user), amt, 1);
    }

    function testSetFeeRecipient() public {
        vm.startPrank(poolOwner);
        superPool.setFeeRecipient(feeTo);
        assertEq(superPool.feeRecipient(), feeTo);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert();
        superPool.setFeeRecipient(user);
    }

    function testSetSuperPoolCap() public {
        vm.startPrank(poolOwner);
        superPool.setSuperpoolCap(1_000_000 ether);
        assertEq(superPool.superPoolCap(), 1_000_000 ether);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert();
        superPool.setSuperpoolCap(1_000_000 ether);
    }

    function testSetSuperPoolFee() public {
        vm.startPrank(poolOwner);
        superPool.setFee(0.04 ether);
        assertEq(superPool.fee(), 0.04 ether);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert();
        superPool.setFee(0.04 ether);
    }

    function testToggleAllocator() public {
        vm.startPrank(poolOwner);

        address newAllocator = makeAddr("NewAllocator");

        superPool.toggleAllocator(newAllocator);
        assertEq(superPool.isAllocator(newAllocator), true);
        superPool.toggleAllocator(newAllocator);
        assertEq(superPool.isAllocator(newAllocator), false);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert();
        superPool.toggleAllocator(makeAddr("BadAllocator"));
    }

    function invariantMaxDepositsStayConsistent() public view {
        uint256 maxDepositAssets = superPool.maxDeposit(user);
        uint256 maxDepositShares = superPool.maxMint(user);

        assertApproxEqAbs(maxDepositShares, superPool.convertToShares(maxDepositAssets), 1);
    }

    function testMaxDepositIncreasesWithHigherCap() public {
        vm.startPrank(poolOwner);
        superPool.setSuperpoolCap(100 ether);
        vm.stopPrank();

        vm.startPrank(user);
        uint256 maxDepositAssets = superPool.maxDeposit(user);
        uint256 maxDepositShares = superPool.maxMint(user);
        vm.stopPrank();

        assertApproxEqAbs(maxDepositShares, superPool.convertToShares(maxDepositAssets), 1);

        vm.startPrank(poolOwner);
        superPool.setSuperpoolCap(200 ether);
        vm.stopPrank();

        vm.startPrank(user);
        uint256 newMaxDepositAssets = superPool.maxDeposit(user);
        uint256 newMaxDepositShares = superPool.maxMint(user);
        vm.stopPrank();

        assertApproxEqAbs(newMaxDepositShares, superPool.convertToShares(newMaxDepositAssets), 1);
        assertGt(newMaxDepositAssets, maxDepositAssets);
        assertGt(newMaxDepositShares, maxDepositShares);
    }

    function testSupplyMoreThanCurrentPoolCaps() public {
        vm.startPrank(poolOwner);
        superPool.setPoolCap(fixedRatePool, 100 ether);
        superPool.setPoolCap(linearRatePool, 100 ether);
        vm.stopPrank();

        vm.startPrank(user);
        asset1.mint(user, 201 ether);
        asset1.approve(address(superPool), 201 ether);
        superPool.deposit(200 ether, user);

        superPool.deposit(1 ether, user);
        assertEq(asset1.balanceOf(address(superPool)), 1 ether);
    }

    function invariantMaxWithdrawalsStayConsistent() public view {
        uint256 maxWithdrawAssets = superPool.maxWithdraw(user);
        uint256 maxWithdrawShares = superPool.maxRedeem(user);

        assertApproxEqAbs(maxWithdrawAssets, superPool.convertToAssets(maxWithdrawShares), 1);
    }

    function testMaxWithdrawDecreasesAsYouWithdraw() public {
        testSimpleDepositIntoSuperpool();

        uint256 maxWithdrawAssets = superPool.maxWithdraw(user);
        uint256 maxWithdrawShares = superPool.maxRedeem(user);

        assertEq(maxWithdrawAssets, 100 ether);
        assertApproxEqAbs(maxWithdrawAssets, superPool.convertToAssets(maxWithdrawShares), 1);

        vm.startPrank(user);
        superPool.withdraw(50 ether, user, user);
        vm.stopPrank();

        uint256 newMaxWithdrawAssets = superPool.maxWithdraw(user);
        uint256 newMaxWithdrawShares = superPool.maxRedeem(user);

        assertEq(newMaxWithdrawAssets, 50 ether);
        assertLt(newMaxWithdrawAssets, maxWithdrawAssets);
        assertLt(newMaxWithdrawShares, maxWithdrawShares);
    }

    function testAMoreComplexScenario() public {
        // 1. Initialize FixedRatePool and LinearRatePool each with a 50 ether cap
        // 2. User1, and User2 each deposit 50 ether into the superpool
        // 3. Lower the cap on FixedRatePool by 10 ether, raise it on LinearRatePool by the same
        // 4. ReAllocate
        // 5. Both users withdraw fully

        vm.startPrank(poolOwner);
        superPool.setPoolCap(fixedRatePool, 50 ether);
        superPool.setPoolCap(linearRatePool, 50 ether);
        vm.stopPrank();

        vm.startPrank(user);
        asset1.mint(user, 50 ether);
        asset1.approve(address(superPool), 50 ether);
        superPool.deposit(50 ether, user);
        vm.stopPrank();

        vm.startPrank(user2);
        asset1.mint(user2, 50 ether);
        asset1.approve(address(superPool), 50 ether);
        superPool.deposit(50 ether, user2);
        vm.stopPrank();

        vm.startPrank(poolOwner);
        superPool.setPoolCap(fixedRatePool, 40 ether);
        superPool.setPoolCap(linearRatePool, 60 ether);
        vm.stopPrank();

        SuperPool.ReallocateParams[] memory reAllocateDeposits = new SuperPool.ReallocateParams[](1);
        SuperPool.ReallocateParams[] memory reAllocateWithdrawals = new SuperPool.ReallocateParams[](1);

        superPool.accrue();

        reAllocateDeposits[0] = (SuperPool.ReallocateParams(fixedRatePool, 10 ether));
        reAllocateWithdrawals[0] = (SuperPool.ReallocateParams(linearRatePool, 10 ether));

        vm.startPrank(user);
        vm.expectRevert();
        superPool.reallocate(reAllocateWithdrawals, reAllocateDeposits); // Regular user cannot reallocate
        vm.stopPrank();

        vm.prank(poolOwner);
        superPool.reallocate(reAllocateWithdrawals, reAllocateDeposits);

        vm.startPrank(user);
        superPool.withdraw(50 ether, user, user);
        vm.stopPrank();

        vm.startPrank(user2);
        superPool.withdraw(50 ether, user2, user2);
        vm.stopPrank();
    }

    function testReallocateDeposits() public {
        vm.startPrank(poolOwner);
        superPool.setPoolCap(fixedRatePool, 50 ether);
        superPool.setPoolCap(linearRatePool, 50 ether);
        superPool.setPoolCap(fixedRatePool2, 50 ether);
        superPool.setPoolCap(linearRatePool2, 50 ether);
        vm.stopPrank();

        uint256[] memory newWrongDepositOrder = new uint256[](3);
        newWrongDepositOrder[0] = fixedRatePool;
        newWrongDepositOrder[1] = linearRatePool;
        newWrongDepositOrder[2] = fixedRatePool2;
        // newDepositOrder[3] = linearRatePool2;

        vm.expectRevert();
        superPool.reorderDepositQueue(newWrongDepositOrder);

        vm.startPrank(poolOwner);

        vm.expectRevert();
        superPool.reorderDepositQueue(newWrongDepositOrder);

        uint256[] memory newDepositOrder = new uint256[](4);
        newDepositOrder[0] = fixedRatePool;
        newDepositOrder[1] = linearRatePool;
        newDepositOrder[2] = fixedRatePool2;
        newDepositOrder[3] = linearRatePool2;

        superPool.reorderDepositQueue(newDepositOrder);
        vm.stopPrank();

        assertEq(superPool.depositQueue(0), fixedRatePool);
        assertEq(superPool.depositQueue(1), linearRatePool);
        assertEq(superPool.depositQueue(2), fixedRatePool2);
        assertEq(superPool.depositQueue(3), linearRatePool2);
    }

    function testReorderWithdrawals() public {
        vm.startPrank(poolOwner);
        superPool.setPoolCap(fixedRatePool, 50 ether);
        superPool.setPoolCap(linearRatePool, 50 ether);
        superPool.setPoolCap(fixedRatePool2, 50 ether);
        superPool.setPoolCap(linearRatePool2, 50 ether);
        vm.stopPrank();

        uint256[] memory newWrongWithdrawalOrder = new uint256[](100);
        newWrongWithdrawalOrder[0] = fixedRatePool;

        vm.expectRevert();
        superPool.reorderWithdrawQueue(newWrongWithdrawalOrder);

        vm.startPrank(poolOwner);
        vm.expectRevert(abi.encodeWithSelector(SuperPool.SuperPool_QueueLengthMismatch.selector, address(superPool)));
        superPool.reorderWithdrawQueue(newWrongWithdrawalOrder);

        uint256[] memory newWithdrawalOrder = new uint256[](4);
        newWithdrawalOrder[0] = fixedRatePool;
        newWithdrawalOrder[1] = linearRatePool;
        newWithdrawalOrder[2] = fixedRatePool2;
        newWithdrawalOrder[3] = linearRatePool2;

        superPool.reorderWithdrawQueue(newWithdrawalOrder);

        assertEq(superPool.withdrawQueue(0), fixedRatePool);
        assertEq(superPool.withdrawQueue(1), linearRatePool);
        assertEq(superPool.withdrawQueue(2), fixedRatePool2);
        assertEq(superPool.withdrawQueue(3), linearRatePool2);
    }

    function testInterestEarnedOnTheUnderlingPool() public {
        // 1. Setup a basic pool with an asset1
        // 2. Add it to the superpool
        // 3. Deposit assets into the pool
        // 4. Borrow from an alternate account
        // 5. accrueInterest
        // 6. Attempt to withdraw all of the liquidity, and see the running out of the pool
        vm.startPrank(poolOwner);
        superPool.setPoolCap(fixedRatePool, 50 ether);
        superPool.setPoolCap(linearRatePool, 50 ether);
        vm.stopPrank();

        vm.startPrank(user);
        asset1.mint(user, 50 ether);
        asset1.approve(address(superPool), 50 ether);

        vm.expectRevert();
        superPool.deposit(0, user);

        superPool.deposit(50 ether, user);
        vm.stopPrank();

        vm.startPrank(Pool(pool).positionManager());
        Pool(pool).borrow(linearRatePool, user, 35 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 5_000_000);
        pool.accrue(linearRatePool);

        vm.startPrank(Pool(pool).positionManager());
        uint256 borrowsOwed = pool.getBorrowsOf(linearRatePool, user);

        asset1.mint(Pool(pool).positionManager(), borrowsOwed);
        asset1.approve(address(pool), borrowsOwed);
        Pool(pool).repay(linearRatePool, user, borrowsOwed);
        vm.stopPrank();

        superPool.accrue();

        vm.startPrank(user);
        vm.expectRevert(); // Not enough liquidity
        superPool.withdraw(40 ether, user, user);
        vm.stopPrank();

        vm.startPrank(poolOwner);
        vm.expectRevert(); // Cant remove a pool with liquidity in it
        superPool.setPoolCap(fixedRatePool, 0 ether);
        vm.stopPrank();
    }
}
