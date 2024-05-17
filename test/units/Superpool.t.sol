// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseTest.t.sol";

import { console } from "forge-std/console.sol";

contract SuperPoolUnitTests is BaseTest {

    SuperPool public superPool;
    address public feeTo = makeAddr("FeeTo");

    function setUp() public override {
        super.setUp();

        SuperPool.SuperPoolInitParams memory params = SuperPool.SuperPoolInitParams({
            asset: address(asset1),
            feeRecipient: feeTo,
            fee: 0.01 ether,
            superPoolCap: 1_000_000 ether,
            name: "test",
            symbol: "test"
        });
        
        superPool = SuperPool(superPoolFactory.deploy(poolOwner, params));
    }

    function testInitSuperPoolFactory() public {
        SuperPoolFactory superPoolFactory = new SuperPoolFactory(address(pool));
        assertEq(superPoolFactory.POOL(), address(pool));
    }

    function testDeployAPoolFromFactory() public {
        address feeRecipient = makeAddr("FeeRecipient");

        SuperPool.SuperPoolInitParams memory params = SuperPool.SuperPoolInitParams({
            asset: address(asset1),
            feeRecipient: feeRecipient,
            fee: 0,
            superPoolCap: 0,
            name: "test",
            symbol: "test"
        });

        address deployed = superPoolFactory.deploy(poolOwner, params);

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
    }

    function testRemovePoolFromSuperPool() public {
        vm.startPrank(poolOwner);
        superPool.setPoolCap(linearRatePool, 100 ether);

        assertEq(superPool.getPoolCount(), 1);
        assertEq(superPool.pools().length, 1);
        assertEq(superPool.poolCap(linearRatePool), 100 ether);

        superPool.setPoolCap(linearRatePool, 0);

        assertEq(superPool.getPoolCount(), 0);
        assertEq(superPool.pools().length, 0);
        assertEq(superPool.poolCap(linearRatePool), 0);
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

        superPool.deposit(100 ether, user);

        assertEq(asset1.balanceOf(address(pool)), 100 ether);
    }

    function testSimpleDepositIntoMultiplePools() public {
        vm.startPrank(poolOwner);
        superPool.setPoolCap(linearRatePool, 100 ether);
        superPool.setPoolCap(fixedRatePool, 100 ether);
        vm.stopPrank();

        vm.startPrank(user);

        asset1.mint(user, 200 ether);
        asset1.approve(address(superPool), 200 ether);

        // Shares and Assets 1:1 before interest is eanred
        superPool.mint(200 ether, user);

        assertEq(asset1.balanceOf(address(pool)), 200 ether);
    }

    function testCannotDepositMoreThanPoolCap() public {
        vm.startPrank(poolOwner);
        superPool.setPoolCap(linearRatePool, 50 ether);
        vm.stopPrank();

        vm.startPrank(user);
        asset1.mint(user, 100 ether);
        asset1.approve(address(superPool), 100 ether);

        vm.expectRevert();
        superPool.deposit(100 ether, user);
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

        superPool.deposit(amt, user);

        console.log("traces after here");

        uint256 expectedAssets = superPool.previewRedeem(amt / 2);
        uint256 assets = superPool.redeem(amt / 2, user, user);
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

    function invariantMaxDepositsStayConsistent() view public {
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

    function invariantMaxWithdrawalsStayConsistent() view public {
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

        reAllocateDeposits[0] = (SuperPool.ReallocateParams(fixedRatePool, 10 ether));
        reAllocateWithdrawals[0] = (SuperPool.ReallocateParams(linearRatePool, 10 ether));

        vm.prank(poolOwner);
        superPool.reallocate(reAllocateWithdrawals, reAllocateDeposits);

        vm.startPrank(user);
        superPool.withdraw(50 ether, user, user);
        vm.stopPrank();

        vm.startPrank(user2);
        superPool.withdraw(50 ether, user2, user2);
        vm.stopPrank();
    }

}

