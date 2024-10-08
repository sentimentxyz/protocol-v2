// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTest, MockSwap } from "../BaseTest.t.sol";
import { Pool } from "src/Pool.sol";
import { Action, Operation } from "src/PositionManager.sol";
import { PositionManager } from "src/PositionManager.sol";
import { Registry } from "src/Registry.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { SuperPool } from "src/SuperPool.sol";
import { SuperPoolFactory } from "src/SuperPoolFactory.sol";
import { FixedRateModel } from "src/irm/FixedRateModel.sol";
import { LinearRateModel } from "src/irm/LinearRateModel.sol";
import { PortfolioLens } from "src/lens/PortfolioLens.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";

contract BigTest is BaseTest {
    Pool pool;
    Registry registry;
    RiskEngine riskEngine;
    PortfolioLens portfolioLens;
    PositionManager positionManager;
    SuperPoolFactory superPoolFactory;

    FixedPriceOracle asset1Oracle;
    FixedPriceOracle asset2Oracle;
    FixedPriceOracle asset3Oracle;

    function setUp() public override {
        super.setUp();

        pool = protocol.pool();
        registry = protocol.registry();
        riskEngine = protocol.riskEngine();
        portfolioLens = protocol.portfolioLens();
        positionManager = protocol.positionManager();
        superPoolFactory = protocol.superPoolFactory();

        asset1Oracle = new FixedPriceOracle(10e18);
        asset2Oracle = new FixedPriceOracle(10e18);
        asset3Oracle = new FixedPriceOracle(10e18);

        vm.startPrank(protocolOwner);
        riskEngine.setOracle(address(asset1), address(asset1Oracle));
        riskEngine.setOracle(address(asset2), address(asset2Oracle));
        riskEngine.setOracle(address(asset3), address(asset3Oracle));
        vm.stopPrank();

        address fixedRateModel = address(new FixedRateModel(1e18));
        address linearRateModel = address(new LinearRateModel(1e18, 2e18));
        address fixedRateModel2 = address(new FixedRateModel(2e18));

        bytes32 BIG_RATE_MODEL_KEY = 0x199ad5d279eb979be68ff9a70e3cdbfde6d1db68fbafaae562d8bf550876df66;
        bytes32 BIG_RATE_MODEL2_KEY = 0xe4ac42ec0e5155ec53437786f05f6965eaaa6ca6bf14e6ec63cf272ec067d8c5;
        bytes32 BIG_RATE_MODEL3_KEY = 0x3c8173df5c36ecb50abea64f9912b8e8c6265f00eb5a4ea7a7e6e4141e5a091e;

        vm.startPrank(protocolOwner);
        registry.setRateModel(BIG_RATE_MODEL_KEY, fixedRateModel);
        registry.setRateModel(BIG_RATE_MODEL2_KEY, linearRateModel);
        registry.setRateModel(BIG_RATE_MODEL3_KEY, fixedRateModel2);
        vm.stopPrank();

        asset1.mint(poolOwner, 3e7);
        vm.startPrank(poolOwner);
        asset1.approve(address(pool), 3e7);
        fixedRatePool = pool.initializePool(
            poolOwner, address(asset1), BIG_RATE_MODEL_KEY, type(uint256).max, type(uint256).max, 1e7
        );
        linearRatePool = pool.initializePool(
            poolOwner, address(asset1), BIG_RATE_MODEL2_KEY, type(uint256).max, type(uint256).max, 1e7
        );
        fixedRatePool2 = pool.initializePool(
            poolOwner, address(asset1), BIG_RATE_MODEL3_KEY, type(uint256).max, type(uint256).max, 1e7
        );
        vm.stopPrank();

        vm.startPrank(poolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset3), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset3));
        riskEngine.requestLtvUpdate(linearRatePool, address(asset2), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset2));

        riskEngine.requestLtvUpdate(fixedRatePool, address(asset3), 0.75e18);
        riskEngine.acceptLtvUpdate(fixedRatePool, address(asset3));
        riskEngine.requestLtvUpdate(fixedRatePool, address(asset2), 0.75e18);
        riskEngine.acceptLtvUpdate(fixedRatePool, address(asset2));

        riskEngine.requestLtvUpdate(fixedRatePool2, address(asset3), 0.75e18);
        riskEngine.acceptLtvUpdate(fixedRatePool2, address(asset3));
        riskEngine.requestLtvUpdate(fixedRatePool2, address(asset2), 0.75e18);
        riskEngine.acceptLtvUpdate(fixedRatePool2, address(asset2));

        riskEngine.toggleAllowedPoolPair(fixedRatePool, linearRatePool);
        riskEngine.toggleAllowedPoolPair(linearRatePool, fixedRatePool);
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
        uint256 initialDepositAmt = 1e7;

        vm.prank(protocolOwner);
        asset1.mint(address(this), initialDepositAmt);
        asset1.approve(address(superPoolFactory), initialDepositAmt);

        SuperPool superPool = SuperPool(
            superPoolFactory.deploySuperPool(
                poolOwner, address(asset1), feeTo, 0.01 ether, 1_000_000 ether, initialDepositAmt, "test", "test"
            )
        );

        // 2. Make a SuperPool with the 3 pools
        vm.startPrank(poolOwner);
        superPool.addPool(fixedRatePool, 100 ether);
        superPool.addPool(fixedRatePool2, 100 ether);
        superPool.addPool(linearRatePool, 100 ether);
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

        bytes memory data = abi.encodeWithSelector(SWAP_FUNC_SELECTOR, address(asset1), address(asset3), 30 ether);

        Action[] memory actions = new Action[](7);
        actions[0] = addToken(address(asset2));
        actions[1] = deposit(address(asset2), 300 ether);
        actions[2] = borrow(fixedRatePool, 15 ether);
        actions[3] = borrow(linearRatePool, 15 ether);
        actions[4] = approve(address(mockswap), address(asset1), 30 ether);
        actions[5] = exec(address(mockswap), 0, data);
        actions[6] = addToken(address(asset3));

        positionManager.processBatch(position, actions);
        vm.stopPrank();

        // 5. Advance time
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + (365 days / 12));

        // 6. User2 repays the borrowed amount
        vm.startPrank(user2);
        pool.accrue(fixedRatePool);
        uint256 debt = pool.getBorrowsOf(fixedRatePool, position);
        uint256 debt2 = pool.getBorrowsOf(linearRatePool, position);

        asset1.mint(position, debt + debt2);

        Action memory _repay = Action({ op: Operation.Repay, data: abi.encode(fixedRatePool, debt) });
        positionManager.process(position, _repay);

        _repay = Action({ op: Operation.Repay, data: abi.encode(linearRatePool, debt2) });
        positionManager.process(position, _repay);
        vm.stopPrank();

        // 7. User should have profit from the borrowed amount
        vm.startPrank(user);
        superPool.accrue();
        uint256 superPoolMaxWithdraw = superPool.maxWithdraw(user);
        assertTrue(superPoolMaxWithdraw > initialAmountCanBeWithdrawn);
        vm.stopPrank();
    }
}
