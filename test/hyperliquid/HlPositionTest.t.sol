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
    address constant OWNER = 0xA89ADa44E48380e61D59887Fa3EFc14373Efd063;

    Pool constant POOL = Pool(0xA845F26dc7ecEc6fbC8f2E0C1eEB41EB6f4fC34C);
    MockERC20 constant USDC = MockERC20(0x3e8aAB9Aad036f37bFC52B9Ae0B99AE1CB0C3959);
    MockERC20 constant HYPE = MockERC20(0x13C34BDf455Eacc3907a23363094d6f36d8603ea);
    RiskEngine constant RISK_ENGINE = RiskEngine(0x83D69EC5dBd6b58e2Ba9C115b5949c8dDd1D14F7);
    PortfolioLens constant PORTFOLIO_LENS = PortfolioLens(0x3C3ee15c91f254c571E99f0A935efA9A152B6aF7);
    PositionManager constant POSITION_MANAGER = PositionManager(0x0404ef74CcBa8Ff746509F375D024A030b1C6f79);

    uint256 constant LP1_AMT = 1e12; // 1e11 = 100k USDC
    uint256 constant GUY_COL_AMT = 100e18;
    uint256 constant GUY_BOR_AMT = 10_000e6;
    uint256 constant HYPE_USDC_POOL =
        69_988_853_007_494_869_570_679_472_471_558_759_754_575_509_158_247_760_694_841_827_597_378_811_233_810;

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
