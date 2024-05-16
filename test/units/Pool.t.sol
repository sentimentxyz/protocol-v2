// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseTest.t.sol";

contract PoolUnitTests is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function testIntializePool() public {
        assertEq(address(pool.REGISTRY()), address(registry));

        address rateModel = address(new LinearRateModel(1e18, 2e18));
        uint256 id = pool.initializePool(poolOwner, address(asset1), rateModel, 0, 0, type(uint128).max);
        assertEq(rateModel, pool.getRateModelFor(id));
    }

    /// @dev Foundry "fails" keyword
    function testFailsDoubleInit() public {
        address rateModel = address(new LinearRateModel(1e18, 2e18));

        pool.initializePool(poolOwner, address(asset1), rateModel, 0, 0, type(uint128).max);
        pool.initializePool(poolOwner, address(asset1), rateModel, 0, 0, type(uint128).max);
    }

    function testCannotFrontRunDeployment() public {
        address notPoolOwner = makeAddr("notPoolOwner");
        address rateModel = address(new LinearRateModel(1e18, 2e18));

        vm.prank(poolOwner);
        uint256 id = pool.initializePool(poolOwner, address(asset1), rateModel, 0, 0, type(uint128).max);

        vm.prank(notPoolOwner);
        uint256 id2 = pool.initializePool(notPoolOwner, address(asset1), rateModel, 0, 0, type(uint128).max);

        assert(id != id2);
    }

    function testCannotDepositNothing() public {
        vm.startPrank(user);
        asset1.approve(address(pool), 0);

        vm.expectRevert("ZERO_SHARES");
        pool.deposit(linearRatePool, 0, user);
    }

    function testCanDepositAssets(uint96 assets) public {
        vm.assume(assets > 0);
        vm.startPrank(user);

        asset1.mint(user, assets);
        asset1.approve(address(pool), assets);

        pool.deposit(linearRatePool, assets, user);

        assertEq(pool.getAssetsOf(linearRatePool, user), assets);
        assertEq(pool.balanceOf(user, linearRatePool), assets); // Shares equal 1:1 at first

        assertEq(asset1.balanceOf(user), 0);
        vm.stopPrank();
    }

    function testCanWithdrawAssets(uint96 assets) public {
        testCanDepositAssets(assets);

        vm.prank(user);
        pool.redeem(linearRatePool, assets, user, user);

        assertEq(pool.getAssetsOf(linearRatePool, user), 0);
        assertEq(pool.balanceOf(user, linearRatePool), 0);

        assertEq(asset1.balanceOf(user), assets);
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

        assertEq(asset1.balanceOf(approvedUser), assets);
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

        assertEq(asset1.balanceOf(operator), assets);
    }

    function testOnlyPositionManagerCanBorrow() public {
        address notPositionManager = makeAddr("notPositionManager");
        vm.startPrank(notPositionManager);
        vm.expectRevert(
            abi.encodeWithSelector(Pool.Pool_OnlyPositionManager.selector, linearRatePool, notPositionManager)
        );
        pool.borrow(linearRatePool, notPositionManager, 100 ether);
    }

    function testCannotBorrowZeroShares(uint96 assets) public {
        testCanDepositAssets(assets);

        vm.startPrank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));

        vm.expectRevert(abi.encodeWithSelector(Pool.Pool_ZeroSharesBorrow.selector, linearRatePool, uint256(0)));
        pool.borrow(linearRatePool, user, 0);
    }

    function testBorrowWorksAsIntended(uint96 _assets) public {
        vm.assume(_assets > 1_000);
        testCanDepositAssets(_assets);

        uint256 assets = uint256(_assets);

        vm.prank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));
        pool.borrow(linearRatePool, user, assets / 5);

        assertEq(pool.getAssetsOf(linearRatePool, user), assets);
        assertApproxEqAbs(asset1.balanceOf(address(pool)), assets * 4 / 5, 1);
        assertApproxEqAbs(asset1.balanceOf(user), assets / 5, 1);

        assertEq(pool.getBorrowsOf(linearRatePool, user), assets / 5);
        assertEq(pool.getTotalBorrows(linearRatePool), assets / 5);
    }

    function testTimeIncreasesDebt(uint96 assets) public {
        testBorrowWorksAsIntended(assets);

        (,,,,,,,, Pool.Uint128Pair memory totalBorrows) = pool.poolDataFor(linearRatePool);

        uint256 time = block.timestamp + 1 days;
        vm.warp(time + 86400 * 7);
        vm.roll(block.number + ((86400 * 7) / 2));

        pool.accrue(linearRatePool);

        (,,,,,,,, Pool.Uint128Pair memory newTotalBorrows) = pool.poolDataFor(linearRatePool);

        assertEq(newTotalBorrows.shares, totalBorrows.shares);
        assertGt(newTotalBorrows.assets, totalBorrows.assets);
    }

    function testCanWithdrawEarnedInterest(uint96 assets) public {
        testTimeIncreasesDebt(assets);

        (,,,,,,,, Pool.Uint128Pair memory borrows) = pool.poolDataFor(linearRatePool);

        assertGt(borrows.assets, borrows.shares);

        // Add some liquidity to the pool
        address user2 = makeAddr("user2");
        vm.startPrank(user2);
        asset1.mint(user2, assets);
        asset1.approve(address(pool), assets);
        pool.deposit(linearRatePool, assets, user2);

        vm.startPrank(user);
        pool.redeem(linearRatePool, pool.balanceOf(user, linearRatePool), user, user);

        assertGt(asset1.balanceOf(user), assets);
    }

    function testRepayWorksAsIntended(uint96 assets) public {
        testBorrowWorksAsIntended(assets);

        uint256 borrowed = pool.getBorrowsOf(linearRatePool, user);

        vm.prank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));
        pool.repay(linearRatePool, user, borrowed / 2);

        assertApproxEqAbs(pool.getBorrowsOf(linearRatePool, user), borrowed / 2, 1);
        assertApproxEqAbs(pool.getTotalBorrows(linearRatePool), borrowed / 2, 1);
    }

    function testConvertToSharesAndAssetsAreReversible(uint112 frac1, uint96 number) public view {
        vm.assume(frac1 > 1e8);
        vm.assume(number > 0);

        Pool.Uint128Pair memory rebase = Pool.Uint128Pair(uint128(frac1) * 2, uint128(frac1));

        uint256 sharesFromAssets = pool.convertToShares(rebase, number);
        uint256 assetsFromShares = pool.convertToAssets(rebase, sharesFromAssets);

        assertApproxEqAbs(assetsFromShares, number, 2);
    }

    function testCantRepayForSomeoneElse() public {
        testBorrowWorksAsIntended(100 ether);

        uint256 borrowed = pool.getBorrowsOf(linearRatePool, user);

        vm.startPrank(makeAddr("notPositionManager"));

        vm.expectRevert();
        pool.repay(linearRatePool, user, borrowed / 2);
    }

    function testCannotRepayZero() public {
        testBorrowWorksAsIntended(100 ether);

        vm.startPrank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));
        vm.expectRevert();
        pool.repay(linearRatePool, user, 0);
    }
}
