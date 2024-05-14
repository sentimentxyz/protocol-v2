// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseTest.t.sol";

contract PoolUnitTests is BaseTest {
    address poolOwner = makeAddr("poolOwner");

    function testIntializePool() public {
        address rateModel = address(new LinearRateModel(1e18, 2e18));
        uint256 id = pool.initializePool(address(0x05), address(asset), rateModel, 0, 0);
        assertEq(rateModel, pool.getRateModelFor(id));
    }

    /// @dev Foundry "fails" keyword
    function testFailsDoubleInit() public {
        address rateModel = address(new LinearRateModel(1e18, 2e18));

        pool.initializePool(poolOwner, address(asset), rateModel, 0, 0);
        pool.initializePool(poolOwner, address(asset), rateModel, 0, 0);
    }

    function testCannotFrontRunDeployment() public {
        address notPoolOwner = makeAddr("notPoolOwner");
        address rateModel = address(new LinearRateModel(1e18, 2e18));

        vm.prank(poolOwner);
        uint256 id = pool.initializePool(poolOwner, address(asset), rateModel, 0, 0);

        vm.prank(notPoolOwner);
        uint256 id2 = pool.initializePool(notPoolOwner, address(asset), rateModel, 0, 0);

        assert(id != id2);
    }

    function testCannotDepositNothing() public {
        vm.startPrank(user);
        asset.approve(address(pool), 0);

        vm.expectRevert("ZERO_SHARES");
        pool.deposit(linearRatePool, 0, user);
    }

    function testCanDepositAssets(uint96 assets) public {
        vm.assume(assets > 0);
        vm.startPrank(user);

        asset.mint(user, assets);
        asset.approve(address(pool), assets);

        pool.deposit(linearRatePool, assets, user);

        assertEq(pool.getAssetsOf(linearRatePool, user), assets);
        assertEq(pool.balanceOf(user, linearRatePool), assets); // Shares equal 1:1 at first

        assertEq(asset.balanceOf(user), 0);
        vm.stopPrank();
    }

    function testCanWithdrawAssets(uint96 assets) public {
        testCanDepositAssets(assets);

        vm.prank(user);
        pool.redeem(linearRatePool, assets, user, user);

        assertEq(pool.getAssetsOf(linearRatePool, user), 0);
        assertEq(pool.balanceOf(user, linearRatePool), 0);

        assertEq(asset.balanceOf(user), assets);
    }

    function testCannotWithdrawOthersAssets(uint96 assets) public {
        testCanDepositAssets(assets);

        address notLender = makeAddr("notLender");

        vm.startPrank(user);
        vm.expectRevert();
        pool.redeem(linearRatePool, assets, user, notLender);
    }

    function testCannotWithdrawNoAssets() public {
        vm.startPrank(user);

        vm.expectRevert("ZERO_ASSETS");
        pool.redeem(linearRatePool, 0, user, user);
    }

    function testCanWithdrawOthersAssetsWithApproval(uint96 assets) public {
        testCanDepositAssets(assets);

        address approvedUser = makeAddr("approvedUser");

        vm.prank(user);
        pool.approve(approvedUser, linearRatePool, assets);

        vm.prank(approvedUser);
        pool.redeem(linearRatePool, assets, approvedUser, user);

        assertEq(pool.getAssetsOf(linearRatePool, user), 0);
        assertEq(pool.balanceOf(user, linearRatePool), 0);

        assertEq(asset.balanceOf(approvedUser), assets);
    }

    function testOperatorCanManageOthersAssets(uint96 assets) public {
        testCanDepositAssets(assets);

        address operator = makeAddr("operator");

        vm.prank(user);
        pool.setOperator(operator, true);

        vm.prank(operator);
        pool.redeem(linearRatePool, assets, operator, user);

        assertEq(pool.getAssetsOf(linearRatePool, user), 0);
        assertEq(pool.balanceOf(user, linearRatePool), 0);

        assertEq(asset.balanceOf(operator), assets);
    }

    function testOnlyPositionManagerCanBorrow() public {
        address notPositionManager = makeAddr("notPositionManager");
        vm.startPrank(notPositionManager);
        // vm.expectRevert(abi.encodePacked(Pool.Pool_OnlyPositionManager.selector, linearRatePool, notPositionManager));
        vm.expectRevert();
        pool.borrow(linearRatePool, notPositionManager, 100 ether);
    }

    function testCannotBorrowZeroShares(uint96 assets) public {
        testCanDepositAssets(assets);

        vm.startPrank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));

        vm.expectRevert(abi.encodePacked(Pool.Pool_ZeroSharesBorrow.selector, linearRatePool, uint256(0)));
        pool.borrow(linearRatePool, user, 0);
    }

    function testBorrowWorksAsIntended(uint96 _assets) public {
        vm.assume(_assets > 1_000);
        testCanDepositAssets(_assets);

        uint256 assets = uint256(_assets);

        vm.prank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));
        pool.borrow(linearRatePool, user, assets / 5);

        assertEq(pool.getAssetsOf(linearRatePool, user), assets);
        assertApproxEqAbs(asset.balanceOf(address(pool)), assets * 4 / 5, 1);
        assertApproxEqAbs(asset.balanceOf(user), assets / 5, 1);

        assertEq(pool.getBorrowsOf(linearRatePool, user), assets / 5);
        assertEq(pool.getTotalBorrows(linearRatePool), assets / 5);
    }

    function testTimeIncreasesDebt(uint96 assets) public {
        testBorrowWorksAsIntended(assets);

        (,,,,,, Pool.Uint128Pair memory totalBorrows) = pool.poolDataFor(linearRatePool);

        uint256 time = block.timestamp + 1 days;
        vm.warp(time + 86400 * 7);
        vm.roll(block.number + ((86400 * 7) / 2));

        pool.accrue(linearRatePool);

        (,,,,,, Pool.Uint128Pair memory newTotalBorrows) = pool.poolDataFor(linearRatePool);

        assertEq(newTotalBorrows.shares, totalBorrows.shares);
        assertGt(newTotalBorrows.assets, totalBorrows.assets);
    }

    function testCanWithdrawEarnedInterest(uint96 assets) public {
        testTimeIncreasesDebt(assets);

        (,,,,,, Pool.Uint128Pair memory borrows) = pool.poolDataFor(linearRatePool);

        assertGt(borrows.assets, borrows.shares);

        // Add some liquidity to the pool
        address user2 = makeAddr("user2");
        vm.startPrank(user2);
        asset.mint(user2, assets);
        asset.approve(address(pool), assets);
        pool.deposit(linearRatePool, assets, user2);

        vm.startPrank(user);
        pool.redeem(linearRatePool, pool.balanceOf(user, linearRatePool), user, user);

        assertGt(asset.balanceOf(user), assets);
    }

    function testRepayWorksAsIntended(uint96 assets) public {
        testBorrowWorksAsIntended(assets);

        uint256 borrowed = pool.getBorrowsOf(linearRatePool, user);

        vm.prank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));
        pool.repay(linearRatePool, user, borrowed / 2);

        assertApproxEqAbs(pool.getBorrowsOf(linearRatePool, user), borrowed / 2, 1);
        assertApproxEqAbs(pool.getTotalBorrows(linearRatePool), borrowed / 2, 1);
    }
}
