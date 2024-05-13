// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseTest.t.sol";

contract PoolUnitTests is BaseTest {
    function testIntializePool() public {
        address rateModel = address(new LinearRateModel(1e18, 2e18));
        uint256 id = pool.initializePool(address(0x05), address(asset), rateModel, 0, 0);
        assertEq(rateModel, pool.getRateModelFor(id));
    }

    /// @dev Foundry "fails" keyword
    function testFailsDoubleInit() public {
        address rateModel = address(new LinearRateModel(1e18, 2e18));

        pool.initializePool(address(0x05), address(asset), rateModel, 0, 0);
        pool.initializePool(address(0x05), address(asset), rateModel, 0, 0);
    }

    function testCannotFrontRunDeployment() public {
        address rateModel = address(new LinearRateModel(1e18, 2e18));

        vm.prank(address(0x05));
        uint256 id = pool.initializePool(address(0x05), address(asset), rateModel, 0, 0);

        vm.prank(address(0x07));
        uint256 id2 = pool.initializePool(address(0x07), address(asset), rateModel, 0, 0);

        assert(id != id2);
    }

    function testCannotDepositNothing() public {
        vm.startPrank(address(0x8));
        asset.approve(address(pool), 0);

        vm.expectRevert("ZERO_SHARES");
        pool.deposit(linearRatePool, 0, address(0x8));
    }

    function testCanDepositAssets(uint96 assets) public {
        vm.assume(assets > 0);
        vm.startPrank(address(0x8));
    
        asset.mint(address(0x8), assets);
        asset.approve(address(pool), assets);

        pool.deposit(linearRatePool, assets, address(0x8));

        assertEq(pool.getAssetsOf(linearRatePool, address(0x8)), assets);
        assertEq(pool.balanceOf(address(0x8), linearRatePool), assets); // Shares equal 1:1 at first

        assertEq(asset.balanceOf(address(0x8)), 0);
        vm.stopPrank();
    }

    function testCanWithdrawAssets(uint96 assets) public {
        testCanDepositAssets(assets);

        vm.prank(address(0x8));
        pool.redeem(linearRatePool, assets, address(0x8), address(0x8));

        assertEq(pool.getAssetsOf(linearRatePool, address(0x8)), 0);
        assertEq(pool.balanceOf(address(0x8), linearRatePool), 0);

        assertEq(asset.balanceOf(address(0x8)), assets);
    }

    function testCannotWithdrawOthersAssets(uint96 assets) public {
        testCanDepositAssets(assets);

        vm.startPrank(address(0x8));

        vm.expectRevert();
        pool.redeem(linearRatePool, assets, address(0x8), address(0x9));
    }

    function testCannotWithdrawNoAssets() public {
        vm.startPrank(address(0x8));

        vm.expectRevert("ZERO_ASSETS");
        pool.redeem(linearRatePool, 0, address(0x8), address(0x8));
    }

    function testCanWithdrawOthersAssetsWithApproval(uint96 assets) public {
        testCanDepositAssets(assets);

        vm.prank(address(0x8));
        pool.approve(address(0x9), linearRatePool, assets);

        vm.prank(address(0x9));
        pool.redeem(linearRatePool, assets, address(0x9), address(0x8));

        assertEq(pool.getAssetsOf(linearRatePool, address(0x8)), 0);
        assertEq(pool.balanceOf(address(0x8), linearRatePool), 0);

        assertEq(asset.balanceOf(address(0x9)), assets);
    }

    function testOperatorCanManageOthersAssets(uint96 assets) public {
        testCanDepositAssets(assets);

        vm.prank(address(0x8));
        pool.setOperator(address(0x9), true);

        vm.prank(address(0x9));
        pool.redeem(linearRatePool, assets, address(0x9), address(0x8));

        assertEq(pool.getAssetsOf(linearRatePool, address(0x8)), 0);
        assertEq(pool.balanceOf(address(0x8), linearRatePool), 0);

        assertEq(asset.balanceOf(address(0x9)), assets);
    }

    function testOnlyPositionManagerCanBorrow() public {
        vm.startPrank(address(0x8));

        vm.expectRevert(Pool.Pool_OnlyPositionManager.selector);
        pool.borrow(linearRatePool, address(0x7), 100 ether);
    }

    function testCannotBorrowZeroShares(uint96 assets) public {
        testCanDepositAssets(assets);

        vm.startPrank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));

        vm.expectRevert(Pool.Pool_ZeroSharesBorrow.selector);
        pool.borrow(linearRatePool, address(0x8), 0);
    }

    function testBorrowWorksAsIntended(uint96 _assets) public {
        vm.assume(_assets > 1_000);
        testCanDepositAssets(_assets);

        uint256 assets = uint256(_assets);
    
        vm.prank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));
        pool.borrow(linearRatePool, address(0x8), assets / 5);

        assertEq(pool.getAssetsOf(linearRatePool, address(0x8)), assets);
        assertApproxEqAbs(asset.balanceOf(address(pool)), assets * 4 / 5, 1);
        assertApproxEqAbs(asset.balanceOf(address(0x8)), assets / 5, 1);

        assertEq(pool.getBorrowsOf(linearRatePool, address(0x8)), assets / 5);
        assertEq(pool.getTotalBorrows(linearRatePool), assets / 5);
    }

    function testTimeIncreasesDebt(uint96 assets) public {
        testBorrowWorksAsIntended(assets);

        (, , , , , , Pool.Uint128Pair memory totalBorrows) = pool.poolDataFor(linearRatePool);

        uint256 time = block.timestamp + 1 days;
        vm.warp(time + 86400 * 7);
        vm.roll(block.number + ((86400 * 7) / 2));

        pool.accrue(linearRatePool);

        (, , , , , , Pool.Uint128Pair memory newTotalBorrows) = pool.poolDataFor(linearRatePool);

        assertEq(newTotalBorrows.shares, totalBorrows.shares);
        assertGt(newTotalBorrows.assets, totalBorrows.assets);
    }

    function testCanWithdrawEarnedInterest(uint96 assets) public {
        testTimeIncreasesDebt(assets);

        (, , , , , , Pool.Uint128Pair memory borrows) = pool.poolDataFor(linearRatePool);

        assertGt(borrows.assets, borrows.shares);

        // Add some liquidity to the pool
        vm.startPrank(address(0x9));
        asset.mint(address(0x9), assets);
        asset.approve(address(pool), assets);
        pool.deposit(linearRatePool, assets, address(0x9)); 


        vm.startPrank(address(0x8)); 
        pool.redeem(linearRatePool, pool.balanceOf(address(0x8), linearRatePool), address(0x8), address(0x8));

        assertGt(asset.balanceOf(address(0x8)), assets);
    }

    function testRepayWorksAsIntended(uint96 assets) public {
        testBorrowWorksAsIntended(assets);

        uint256 borrowed = pool.getBorrowsOf(linearRatePool, address(0x8));

        vm.prank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));
        pool.repay(linearRatePool, address(0x8), borrowed / 2);

        assertApproxEqAbs(pool.getBorrowsOf(linearRatePool, address(0x8)), borrowed / 2, 1);
        assertApproxEqAbs(pool.getTotalBorrows(linearRatePool), borrowed / 2, 1);
    }
}
