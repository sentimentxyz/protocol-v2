// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTest } from "../BaseTest.t.sol";
import { Pool } from "src/Pool.sol";
import { Action, Operation } from "src/PositionManager.sol";
import { PositionManager } from "src/PositionManager.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { SuperPool } from "src/SuperPool.sol";
import { SuperPoolFactory } from "src/SuperPoolFactory.sol";
import { FixedRateModel } from "src/irm/FixedRateModel.sol";
import { LinearRateModel } from "src/irm/LinearRateModel.sol";
import { PortfolioLens } from "src/lens/PortfolioLens.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";

contract BigTest is BaseTest {
    Pool pool;
    RiskEngine riskEngine;
    PortfolioLens portfolioLens;
    PositionManager positionManager;
    SuperPoolFactory superPoolFactory;

    FixedPriceOracle asset1Oracle;
    FixedPriceOracle asset2Oracle;

    function setUp() public override {
        super.setUp();

        pool = protocol.pool();
        riskEngine = protocol.riskEngine();
        portfolioLens = protocol.portfolioLens();
        positionManager = protocol.positionManager();
        superPoolFactory = protocol.superPoolFactory();

        asset1Oracle = new FixedPriceOracle(10e18);
        asset2Oracle = new FixedPriceOracle(1e18);

        vm.startPrank(protocolOwner);
        riskEngine.setOracle(address(asset1), address(asset1Oracle));
        riskEngine.setOracle(address(asset2), address(asset2Oracle));
        vm.stopPrank();

        address fixedRateModel = address(new FixedRateModel(1e18));
        address linearRateModel = address(new LinearRateModel(1e18, 2e18));
        address fixedRateModel2 = address(new FixedRateModel(2e18));

        vm.startPrank(poolOwner);
        fixedRatePool = pool.initializePool(poolOwner, address(asset1), fixedRateModel, type(uint128).max);
        linearRatePool = pool.initializePool(poolOwner, address(asset1), linearRateModel, type(uint128).max);
        fixedRatePool2 = pool.initializePool(poolOwner, address(asset1), fixedRateModel2, type(uint128).max);
        vm.stopPrank();

        vm.startPrank(poolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset1));
        riskEngine.requestLtvUpdate(linearRatePool, address(asset2), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset2));

        riskEngine.requestLtvUpdate(fixedRatePool, address(asset1), 0.75e18);
        riskEngine.acceptLtvUpdate(fixedRatePool, address(asset1));
        riskEngine.requestLtvUpdate(fixedRatePool, address(asset2), 0.75e18);
        riskEngine.acceptLtvUpdate(fixedRatePool, address(asset2));

        riskEngine.requestLtvUpdate(fixedRatePool2, address(asset1), 0.75e18);
        riskEngine.acceptLtvUpdate(fixedRatePool2, address(asset1));
        riskEngine.requestLtvUpdate(fixedRatePool2, address(asset2), 0.75e18);
        riskEngine.acceptLtvUpdate(fixedRatePool2, address(asset2));
        vm.stopPrank();
    }

    function testMultiPoolProfitScenario() public {
        // 1. Set up 3 pools with a 100 ether cap each
        // 2. Make a SuperPool with the 3 pools
        // 3. User fills up the pool
        // 4. User2 borrows from 2 of the pools
        // 5. Advance time
        // 6. User2 repays the borrowed amount
        // 7. User should have profit from the borrowed amount
        // 8. feeTo should make money
        address feeTo = makeAddr("feeTo");
        SuperPool superPool = SuperPool(
            superPoolFactory.deploySuperPool(
                poolOwner, address(asset1), feeTo, 0.01 ether, 1_000_000 ether, "test", "test"
            )
        );

        // 2. Make a SuperPool with the 3 pools
        vm.startPrank(poolOwner);
        superPool.setPoolCap(fixedRatePool, 100 ether);
        superPool.setPoolCap(fixedRatePool2, 100 ether);
        superPool.setPoolCap(linearRatePool, 100 ether);
        vm.stopPrank();

        // 3. User fills up the pool
        vm.startPrank(user);
        asset1.mint(user, 300 ether);
        asset1.approve(address(superPool), 300 ether);
        superPool.deposit(300 ether, user);

        uint256 initialAmountCanBeWithdrawn = superPool.maxWithdraw(user);
        vm.stopPrank();

        // 4. User2 borrows from 2 of the pools
        vm.startPrank(user2);
        asset2.mint(user2, 300 ether);
        asset2.approve(address(positionManager), 300 ether);

        // Make a new position
        (address position, Action memory _newPosition) = newPosition(user2, "test");
        positionManager.process(position, _newPosition);

        Action memory addNewCollateral = addToken(address(asset2));
        Action memory depositCollateral = deposit(address(asset2), 300 ether);
        Action memory borrowAct = borrow(fixedRatePool, 15 ether);

        Action[] memory actions = new Action[](3);
        actions[0] = addNewCollateral;
        actions[1] = depositCollateral;
        actions[2] = borrowAct;

        positionManager.processBatch(position, actions);
        vm.stopPrank();

        // 5. Advance time
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + (365 days / 12));

        // 6. User2 repays the borrowed amount
        vm.startPrank(user2);
        pool.accrue(fixedRatePool);
        uint256 debt = pool.getBorrowsOf(fixedRatePool, position);

        asset1.mint(position, debt);

        Action memory _repay = Action({ op: Operation.Repay, data: abi.encode(fixedRatePool, debt) });
        positionManager.process(position, _repay);
        vm.stopPrank();

        // 7. User should have profit from the borrowed amount
        vm.startPrank(user);
        superPool.accrue();
        assertTrue(superPool.maxWithdraw(user) > initialAmountCanBeWithdrawn);
        vm.stopPrank();
    }
}
