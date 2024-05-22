// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {PositionManager} from "src/PositionManager.sol";
import {RiskModule} from "src/RiskModule.sol";
import {DebtData, AssetData, Action} from "src/PositionManager.sol";
import {FixedPriceOracle} from "src/oracle/FixedPriceOracle.sol";

contract LiquidationIntTest is BaseTest {
    address public position;
    address public liquidator = makeAddr("liquidator");

    function setUp() public override {
        super.setUp();

        // ZeroOracle zeroOracle = new ZeroOracle();
        FixedPriceOracle oneEthOracle = new FixedPriceOracle(1e18);

        vm.startPrank(protocolOwner);
        riskEngine.setOracle(address(asset1), address(oneEthOracle)); // 1 asset1 = 1 eth
        riskEngine.setOracle(address(asset2), address(oneEthOracle)); // 1 asset2 = 1 eth
        vm.stopPrank();

        vm.startPrank(poolOwner);
        riskEngine.requestLtvUpdate(fixedRatePool, address(asset1), 0.5e18); // 2x lev
        riskEngine.acceptLtvUpdate(fixedRatePool, address(asset1));
        riskEngine.requestLtvUpdate(fixedRatePool, address(asset2), 0.5e18); // 2x lev
        riskEngine.acceptLtvUpdate(fixedRatePool, address(asset2));
        vm.stopPrank();

        asset1.mint(lender, 100e18);
        asset2.mint(user, 10e18);

        vm.startPrank(lender);
        asset1.approve(address(pool), 100e18);
        pool.deposit(fixedRatePool, 100e18, lender);
        vm.stopPrank();
    }

    function testLiquidate() public {
        vm.startPrank(user);
        asset2.approve(address(positionManager), 1e18);

        // deposit 1e18 asset2, borrow 1e18 asset1
        Action[] memory actions = new Action[](5);
        (position, actions[0]) = newPosition(user, bytes32(uint256(0x123456789)));
        actions[1] = deposit(address(asset2), 1e18);
        actions[2] = addToken(address(asset2));
        actions[3] = borrow(fixedRatePool, 1e18);
        actions[4] = addToken(address(asset1));
        positionManager.processBatch(position, actions);
        vm.stopPrank();
        assertTrue(riskEngine.isPositionHealthy(position));

        (uint256 totalAssetValue, uint256 totalDebtValue, uint256 minReqAssetValue) = riskEngine.getRiskData(position);

        assertEq(totalAssetValue, 2e18);
        assertEq(totalDebtValue, 1e18);
        assertEq(minReqAssetValue, 2e18);

        // construct liquidator data
        DebtData memory debtData = DebtData({poolId: fixedRatePool, amt: 1e18});
        DebtData[] memory debts = new DebtData[](1);
        debts[0] = debtData;
        AssetData memory asset1Data = AssetData({asset: address(asset1), amt: 1e18});
        AssetData memory asset2Data = AssetData({asset: address(asset2), amt: 1e18});
        AssetData[] memory assets = new AssetData[](2);
        assets[0] = asset1Data;
        assets[1] = asset2Data;

        // attempt to liquidate before price moves
        asset1.mint(liquidator, 10e18);
        vm.startPrank(liquidator);
        asset1.approve(address(positionManager), 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(PositionManager.PositionManager_LiquidateHealthyPosition.selector, position)
        );
        positionManager.liquidate(position, debts, assets);
        vm.stopPrank();

        // modify asset2 price from 1eth to 0.1eth
        FixedPriceOracle pointOneEthOracle = new FixedPriceOracle(0.1e18);
        vm.prank(protocolOwner);
        riskEngine.setOracle(address(asset2), address(pointOneEthOracle));
        assertFalse(riskEngine.isPositionHealthy(position));

        // liquidate
        vm.startPrank(liquidator);
        asset1.approve(address(positionManager), 1e18);
        positionManager.liquidate(position, debts, assets);
        vm.stopPrank();
    }

    function testSeizeTooMuch() public {
        vm.startPrank(user);
        asset2.approve(address(positionManager), 1e18);

        // deposit 1e18 asset2, borrow 1e18 asset1
        Action[] memory actions = new Action[](5);
        (position, actions[0]) = newPosition(user, bytes32(uint256(0x123456789)));
        actions[1] = deposit(address(asset2), 1e18);
        actions[2] = addToken(address(asset2));
        actions[3] = borrow(fixedRatePool, 1e18);
        actions[4] = addToken(address(asset1));
        positionManager.processBatch(position, actions);
        vm.stopPrank();
        assertTrue(riskEngine.isPositionHealthy(position));

        (uint256 totalAssetValue, uint256 totalDebtValue, uint256 minReqAssetValue) = riskEngine.getRiskData(position);

        assertEq(totalAssetValue, 2e18);
        assertEq(totalDebtValue, 1e18);
        assertEq(minReqAssetValue, 2e18);

        // modify asset2 price from 1eth to 0.1eth
        FixedPriceOracle pointOneEthOracle = new FixedPriceOracle(0.1e18);
        vm.prank(protocolOwner);
        riskEngine.setOracle(address(asset2), address(pointOneEthOracle));
        assertFalse(riskEngine.isPositionHealthy(position));

        // construct liquidator data
        DebtData memory debtData = DebtData({poolId: fixedRatePool, amt: 0.1e18});
        DebtData[] memory debts = new DebtData[](1);
        debts[0] = debtData;
        AssetData memory asset1Data = AssetData({asset: address(asset1), amt: 1e18});
        AssetData memory asset2Data = AssetData({asset: address(asset2), amt: 1e18});
        AssetData[] memory assets = new AssetData[](2);
        assets[0] = asset1Data;
        assets[1] = asset2Data;

        // liquidate
        asset1.mint(liquidator, 10e18);
        vm.startPrank(liquidator);
        asset1.approve(address(positionManager), 1e18);
        vm.expectRevert(abi.encodeWithSelector(RiskModule.RiskModule_SeizedTooMuch.selector, 1.1 ether, 0.12 ether));
        positionManager.liquidate(position, debts, assets);
        vm.stopPrank();
    }
}
