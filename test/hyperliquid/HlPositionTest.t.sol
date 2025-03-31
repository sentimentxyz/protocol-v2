// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { Pool } from "src/Pool.sol";

import { Action, Operation, PositionManager } from "src/PositionManager.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { SuperPool } from "src/SuperPool.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PortfolioLens } from "src/lens/PortfolioLens.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";
import { ActionUtils } from "test/utils/ActionUtils.sol";

contract HlPositionTest is Test {
    using ActionUtils for Action;

    bytes32 constant SALT = "TESTSALT";
    address immutable LP1 = makeAddr("LP1");
    address immutable GUY = makeAddr("GUY");
    address constant OWNER = 0xB290f2F3FAd4E540D0550985951Cdad2711ac34A;

    Pool constant POOL = Pool(0x36BFD6b40e2c9BbCfD36a6B1F1Aa65974f4fFA5D);
    IERC20 constant borrowAsset = IERC20(0x5555555555555555555555555555555555555555);
    IERC20 constant collateralAsset = IERC20(0x94e8396e0869c9F2200760aF0621aFd240E1CF38);
    RiskEngine constant RISK_ENGINE = RiskEngine(0xd22dE451Ba71fA6F06C65962649ba4E2Aea10863);
    PortfolioLens constant PORTFOLIO_LENS = PortfolioLens(0x9700750001dDD7C4542684baC66C64D74fA833c0);
    PositionManager constant POSITION_MANAGER = PositionManager(0xE019Ce6e80dFe505bca229752A1ad727E14085a4);

    uint256 constant LP1_AMT = 300e18;
    uint256 constant GUY_COL_AMT = 30e18;
    uint256 constant GUY_BOR_AMT = 10e18;
    uint256 constant poolId =
        14_778_331_100_793_740_007_929_971_613_900_703_995_604_470_186_100_539_494_274_894_855_699_577_891_585;

    address constant borrowAssetWhale = 0x8D64d8273a3D50E44Cc0e6F43d927f78754EdefB;
    address constant collateralAssetWhale = 0x67e70761E88C77ffF2174d5a4EaD42B44Df3F64a;

    function setUp() public {
        FixedPriceOracle borrowAssetOracle = new FixedPriceOracle(0.1e18); // 1 borrowAsset = 0.1 ETH
        FixedPriceOracle collateralAssetOracle = new FixedPriceOracle(0.1e18); // 1 collateralAsset = 0.1 ETH

        vm.startPrank(OWNER);

        RISK_ENGINE.setOracle(address(borrowAsset), address(borrowAssetOracle));
        RISK_ENGINE.setOracle(address(collateralAsset), address(collateralAssetOracle));
        vm.stopPrank();

        assertEq(RISK_ENGINE.getValueInEth(address(collateralAsset), GUY_COL_AMT), 3e18);
        assertEq(RISK_ENGINE.getValueInEth(address(borrowAsset), 10e18), 1e18);

        // Some tokens do not work with deal()
        vm.prank(borrowAssetWhale);
        borrowAsset.transfer(LP1, LP1_AMT);

        vm.startPrank(LP1);
        //deal(address(borrowAsset), LP1, LP1_AMT);
        borrowAsset.approve(address(POOL), LP1_AMT);
        POOL.deposit(poolId, LP1_AMT, LP1);
        vm.stopPrank();
    }

    function testBorrowborrowAssetForCollateralAsset() public {
        //deal(address(collateralAsset), GUY, GUY_COL_AMT);
        vm.startPrank(collateralAssetWhale);
        collateralAsset.transfer(GUY, GUY_COL_AMT);

        (address position, bool available) = PORTFOLIO_LENS.predictAddress(GUY, SALT);
        assertTrue(available);

        Action[] memory actions = new Action[](5);
        actions[0] = ActionUtils.newPosition(GUY, SALT);
        actions[1] = ActionUtils.deposit(address(collateralAsset), GUY_COL_AMT);
        actions[2] = ActionUtils.addToken(address(collateralAsset));
        actions[3] = ActionUtils.borrow(poolId, GUY_BOR_AMT);
        actions[4] = ActionUtils.transfer(GUY, address(borrowAsset), GUY_BOR_AMT);

        vm.startPrank(GUY);
        collateralAsset.approve(address(POSITION_MANAGER), GUY_COL_AMT);
        POSITION_MANAGER.processBatch(position, actions);
        vm.stopPrank();

        console2.log("GUY borrowAsset: ", borrowAsset.balanceOf(GUY));
        console2.log("GUY collateralAsset: ", collateralAsset.balanceOf(GUY));
    }

    function testRepayBorrowAssetAndWithdrawCollateralAsset() public {
        vm.startPrank(collateralAssetWhale);
        collateralAsset.transfer(GUY, GUY_COL_AMT);
        vm.startPrank(borrowAssetWhale);
        borrowAsset.transfer(GUY, 1); // account for rounding on borrowBalance

        (address position, bool available) = PORTFOLIO_LENS.predictAddress(GUY, SALT);
        assertTrue(available);

        Action[] memory actions = new Action[](5);
        actions[0] = ActionUtils.newPosition(GUY, SALT);
        actions[1] = ActionUtils.deposit(address(collateralAsset), GUY_COL_AMT);
        actions[2] = ActionUtils.addToken(address(collateralAsset));
        actions[3] = ActionUtils.borrow(poolId, GUY_BOR_AMT);
        actions[4] = ActionUtils.transfer(GUY, address(borrowAsset), GUY_BOR_AMT);

        vm.startPrank(GUY);
        collateralAsset.approve(address(POSITION_MANAGER), GUY_COL_AMT);
        POSITION_MANAGER.processBatch(position, actions);
        vm.stopPrank();

        //
        // Repay
        //
        actions = new Action[](4);
        actions[0] = ActionUtils.deposit(address(borrowAsset), GUY_BOR_AMT + 1);
        actions[1] = ActionUtils.repay(poolId, type(uint256).max);
        actions[2] = ActionUtils.removeToken(address(collateralAsset));
        actions[3] = ActionUtils.transfer(GUY, address(collateralAsset), GUY_COL_AMT);

        vm.startPrank(GUY);
        borrowAsset.approve(address(POSITION_MANAGER), GUY_BOR_AMT + 1);
        POSITION_MANAGER.processBatch(position, actions);
        vm.stopPrank();

        console2.log("GUY collateralAsset: ", collateralAsset.balanceOf(GUY));
    }
}
