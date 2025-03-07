// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { Pool } from "src/Pool.sol";

import { Action, Operation, PositionManager } from "src/PositionManager.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { SuperPool } from "src/SuperPool.sol";

import { PortfolioLens } from "src/lens/PortfolioLens.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ActionUtils } from "test/utils/ActionUtils.sol";

contract HlPositionTest is Test {
    using ActionUtils for Action;

    bytes32 constant SALT = "TESTSALT";
    address immutable LP1 = makeAddr("LP1");
    address immutable GUY = makeAddr("GUY");
    address constant OWNER = 0xB290f2F3FAd4E540D0550985951Cdad2711ac34A;

    Pool constant POOL = Pool(0xE5B81a2bdaE122EE8E538CF866d721F09539556F);
    IERC20 constant borrowAsset = IERC20(0x5555555555555555555555555555555555555555);
    IERC20 constant collateralAsset = IERC20(0x94e8396e0869c9F2200760aF0621aFd240E1CF38);
    RiskEngine constant RISK_ENGINE = RiskEngine(0x5f7e170Be9ac684fF221b55B956d95b10eaBA3C8);
    PortfolioLens constant PORTFOLIO_LENS = PortfolioLens(0xF3487f4731f63B9AD94aAEa1F8A97a38Ec64c2E9);
    PositionManager constant POSITION_MANAGER = PositionManager(0xE709523Bf6902b757B1A741187b5c10F2e24e463);

    uint256 constant LP1_AMT = 300e18; 
    uint256 constant GUY_COL_AMT = 30e18;
    uint256 constant GUY_BOR_AMT = 10e18;
    uint256 constant poolId =
        86638265068603793307491732110632390757630691719682137516485622823921024666224;

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
