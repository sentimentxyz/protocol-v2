// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {RiskModule} from "src/RiskModule.sol";
import {Action} from "src/PositionManager.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {FixedPriceOracle} from "src/oracle/FixedPriceOracle.sol";

contract RiskModuleUnitTests is BaseTest {
    address public position;
    FixedPriceOracle oneEthOracle = new FixedPriceOracle(1e18);

    function setUp() public override {
        super.setUp();

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

    function testRiskModuleInit(address testRegistry, uint256 minDebt, uint256 liqDiscount) public {
        RiskModule testRiskModule = new RiskModule(testRegistry, minDebt, liqDiscount);

        assertEq(address(testRiskModule.REGISTRY()), testRegistry);
        assertEq(testRiskModule.LIQUIDATION_DISCOUNT(), liqDiscount);
        assertEq(testRiskModule.MIN_DEBT(), minDebt);
    }

    function testAssetValueFuncs() public {
        vm.startPrank(user);
        asset2.approve(address(positionManager), 1e18);

        // deposit 1e18 asset2, borrow 1e18 asset1
        Action[] memory actions = new Action[](3);
        (position, actions[0]) = newPosition(user, bytes32(uint256(0x123456789)));
        actions[1] = deposit(address(asset2), 1e18);
        actions[2] = addToken(address(asset2));
        positionManager.processBatch(position, actions);
        vm.stopPrank();

        assertEq(riskModule.getTotalAssetValue(position), 1e18);
        assertEq(riskModule.getAssetValue(position, address(asset2)), 1e18);
    }

    function testDebtValueFuncs() public {
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

        assertEq(riskModule.getTotalDebtValue(position), 1e18);
        assertEq(riskModule.getDebtValueForPool(position, fixedRatePool), 1e18);
    }

    function testUnsupportedAsset() public {
        MockERC20 asset3 = new MockERC20("ASSET3", "ASSET3", 18);
        asset3.mint(user, 10e18);

        vm.prank(protocolOwner);
        riskEngine.setOracle(address(asset3), address(oneEthOracle));

        vm.startPrank(user);
        asset3.approve(address(positionManager), 1e18);

        // deposit 1e18 asset3, borrow 1e18 asset1
        Action[] memory actions = new Action[](5);
        (position, actions[0]) = newPosition(user, bytes32(uint256(0x123456789)));
        actions[1] = deposit(address(asset3), 1e18);
        actions[2] = addToken(address(asset3));
        actions[3] = borrow(fixedRatePool, 1e18);
        actions[4] = addToken(address(asset1));
        vm.expectRevert(abi.encodeWithSelector(RiskModule.RiskModule_UnsupportedAsset.selector, fixedRatePool, asset3));
        positionManager.processBatch(position, actions);
        vm.stopPrank();
    }
}
