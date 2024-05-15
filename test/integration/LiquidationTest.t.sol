// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {Action} from "src/PositionManager.sol";
import {FixedPriceOracle} from "src/oracle/FixedPriceOracle.sol";

contract LiquidationIntTest is BaseTest {
    address public position;
    FixedPriceOracle asset1Oracle = new FixedPriceOracle(1e18);
    FixedPriceOracle asset2Oracle = new FixedPriceOracle(1e18);

    function setUp() public override {
        super.setUp();

        vm.startPrank(protocolOwner);
        riskEngine.setOracle(address(asset1), address(asset1Oracle));
        riskEngine.setOracle(address(asset2), address(asset2Oracle));
        vm.stopPrank();

        vm.startPrank(poolOwner);
        riskEngine.requestLtvUpdate(fixedRatePool, address(asset2), 0.5e18); // 2x lev
        riskEngine.acceptLtvUpdate(fixedRatePool, address(asset2));
        riskEngine.requestLtvUpdate(fixedRatePool, address(asset1), 0.9e18); // 2x lev
        riskEngine.acceptLtvUpdate(fixedRatePool, address(asset1));
        vm.stopPrank();

        asset1.mint(lender, 200e18);
        asset2.mint(user, 10e18);

        vm.startPrank(lender);
        asset1.approve(address(pool), 100e18);
        pool.deposit(fixedRatePool, 100e18, lender);
        vm.stopPrank();
    }

    function testLiquidate() public {
        vm.startPrank(user);
        asset2.approve(address(positionManager), 1e18);

        Action[] memory actions = new Action[](5);
        (position, actions[0]) = newPosition(user, bytes32(uint256(0x123456789)));
        actions[1] = deposit(address(asset2), 1e18);
        actions[2] = addToken(address(asset2));
        actions[3] = borrow(fixedRatePool, 1e18);
        actions[4] = addToken(address(asset1));

        positionManager.processBatch(position, actions);
        vm.stopPrank();
    }
}
