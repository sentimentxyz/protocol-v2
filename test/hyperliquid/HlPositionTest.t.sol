// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { Pool } from "src/Pool.sol";

import { Action, Operation, PositionManager } from "src/PositionManager.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { SuperPool } from "src/SuperPool.sol";

import { PortfolioLens } from "src/lens/PortfolioLens.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { ActionUtils } from "test/utils/ActionUtils.sol";

contract HlPositionTest is Test {
    using ActionUtils for Action;

    bytes32 constant SALT = "TESTSALT";
    address immutable LP1 = makeAddr("LP1");
    address immutable GUY = makeAddr("GUY");
    address constant OWNER = 0xB290f2F3FAd4E540D0550985951Cdad2711ac34A;

    Pool constant POOL = Pool(0xCF5e73C836f40fA83ED634259978F9c3A3FC26f8);
    MockERC20 constant USDC = MockERC20(0xdeC702aa5a18129Bd410961215674A7A130A12e5);
    MockERC20 constant HYPE = MockERC20(0xB3fB66C10fD75E7ceB7E491d8dF505De0d91d340);
    RiskEngine constant RISK_ENGINE = RiskEngine(0x71Bc92B8B848c287F82a56EfE1f30a439b1976B2);
    PortfolioLens constant PORTFOLIO_LENS = PortfolioLens(0xE4114fc09A19A2D34E7f9f9DA1C9474070623EFd);
    PositionManager constant POSITION_MANAGER = PositionManager(0x4D088E22F1c659bCDDf9982c6EF23147e5cb309f);

    uint256 constant LP1_AMT = 1e12; // 1e11 = 100k USDC
    uint256 constant GUY_COL_AMT = 100e18;
    uint256 constant GUY_BOR_AMT = 10_000e6;
    uint256 constant HYPE_USDC_POOL =
        102_631_104_641_534_854_069_380_865_616_741_013_922_326_953_286_420_920_971_394_834_166_600_192_052_271;

    function setUp() public {
        FixedPriceOracle usdcOracle = new FixedPriceOracle(25e13); // 1 USDC = 0.00025 ETH
        FixedPriceOracle hypeOracle = new FixedPriceOracle(25e16); // 1 HYPE = 0.25 ETH

        vm.startPrank(OWNER);
        RISK_ENGINE.setOracle(address(USDC), address(usdcOracle));
        RISK_ENGINE.setOracle(address(HYPE), address(hypeOracle));
        vm.stopPrank();

        assertEq(RISK_ENGINE.getValueInEth(address(HYPE), GUY_COL_AMT), 25e18);
        assertEq(RISK_ENGINE.getValueInEth(address(USDC), 1e6), 25e13);

        vm.startPrank(LP1);
        USDC.mint(LP1, LP1_AMT);
        USDC.approve(address(POOL), LP1_AMT);
        POOL.deposit(HYPE_USDC_POOL, LP1_AMT, LP1);
        vm.stopPrank();

        HYPE.mint(GUY, GUY_COL_AMT);
    }

    function testBorrowUsdcForHype() public {
        (address position, bool available) = PORTFOLIO_LENS.predictAddress(GUY, SALT);
        assertTrue(available);

        Action[] memory actions = new Action[](5);
        actions[0] = ActionUtils.newPosition(GUY, SALT);
        actions[1] = ActionUtils.deposit(address(HYPE), GUY_COL_AMT);
        actions[2] = ActionUtils.addToken(address(HYPE));
        actions[3] = ActionUtils.borrow(HYPE_USDC_POOL, GUY_BOR_AMT);
        actions[4] = ActionUtils.transfer(GUY, address(USDC), GUY_BOR_AMT);

        vm.startPrank(GUY);
        HYPE.approve(address(POSITION_MANAGER), GUY_COL_AMT);
        POSITION_MANAGER.processBatch(position, actions);
        vm.stopPrank();

        console2.log("GUY USDC: ", USDC.balanceOf(GUY));
    }

    function testRepayUsdcAndWithdrawHype() public {
        (address position, bool available) = PORTFOLIO_LENS.predictAddress(GUY, SALT);
        assertTrue(available);

        Action[] memory actions = new Action[](5);
        actions[0] = ActionUtils.newPosition(GUY, SALT);
        actions[1] = ActionUtils.deposit(address(HYPE), GUY_COL_AMT);
        actions[2] = ActionUtils.addToken(address(HYPE));
        actions[3] = ActionUtils.borrow(HYPE_USDC_POOL, GUY_BOR_AMT);
        actions[4] = ActionUtils.transfer(GUY, address(USDC), GUY_BOR_AMT);

        vm.startPrank(GUY);
        HYPE.approve(address(POSITION_MANAGER), GUY_COL_AMT);
        POSITION_MANAGER.processBatch(position, actions);
        vm.stopPrank();

        //
        // Repay
        //
        actions = new Action[](4);
        actions[0] = ActionUtils.deposit(address(USDC), GUY_BOR_AMT);
        actions[1] = ActionUtils.repay(HYPE_USDC_POOL, type(uint256).max);
        actions[2] = ActionUtils.removeToken(address(HYPE));
        actions[3] = ActionUtils.transfer(GUY, address(HYPE), GUY_COL_AMT);

        vm.startPrank(GUY);
        USDC.approve(address(POSITION_MANAGER), GUY_BOR_AMT);
        POSITION_MANAGER.processBatch(position, actions);
        vm.stopPrank();

        console2.log("GUY HYPE: ", HYPE.balanceOf(GUY));
    }
}
