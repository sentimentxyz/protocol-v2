// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseTest.t.sol";
import {FixedRateModel} from "../../src/irm/FixedRateModel.sol";
import {LinearRateModel} from "../../src/irm/LinearRateModel.sol";

import { Action, Operation } from "src/PositionManager.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";

contract RiskModuleUnitTests is BaseTest {
    address public owner = address(0x5);
    MockERC20 public collateral = new MockERC20("Collateral", "COL", 18);

    FixedPriceOracle collateralOracle = new FixedPriceOracle(0.5e18);
    FixedPriceOracle assetOracle = new FixedPriceOracle(10e18);

    address public position;

    function setUp() public override {
        super.setUp();

        riskEngine.setOracle(address(collateral), address(collateralOracle));
        riskEngine.setOracle(address(asset), address(assetOracle));

        asset.mint(address(this), 10000 ether);
        asset.approve(address(pool), 10000 ether);

        pool.deposit(linearRatePool, 10000 ether, address(0x9));
    }

    function testOwnerCanUpdateLTV() public {
        uint256 startLtv = riskEngine.ltvFor(linearRatePool, address(asset));
        assertEq(startLtv, 0);

        vm.startPrank(address(0x99));
        riskEngine.requestLtvUpdate(linearRatePool, address(asset), 0.75e18);

        riskEngine.acceptLtvUpdate(linearRatePool, address(asset));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset)), 0.75e18);
    }

    function testOwnerCanRejectLTVUpdated() public {
        // Set a starting non-zero ltv
        vm.startPrank(address(0x99));
        riskEngine.requestLtvUpdate(linearRatePool, address(asset), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset)), 0.75e18);

        riskEngine.requestLtvUpdate(linearRatePool, address(asset), 0.5e18);
        riskEngine.rejectLtvUpdate(linearRatePool, address(asset));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset)), 0.75e18);
    }

    function testNonOwnerCannotUpdateLTV() public {
        vm.prank(address(0x99));
        riskEngine.requestLtvUpdate(linearRatePool, address(asset), 0.75e18);

        vm.startPrank(address(0x90));
        vm.expectRevert();
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset));

        vm.expectRevert();
        riskEngine.rejectLtvUpdate(linearRatePool, address(asset));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset)), 0);
    }

    function testCannotSetLTVOutsideGlobalLimits() public {
        vm.prank(riskEngine.owner());
        riskEngine.setLtvBounds(0.25e18, 1.25e18);

        vm.startPrank(address(0x99));
        vm.expectRevert();
        riskEngine.requestLtvUpdate(linearRatePool, address(asset), 0.24e18);

        vm.expectRevert();
        riskEngine.requestLtvUpdate(linearRatePool, address(asset), 1.26e18);

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset)), 0);
    }

    function testCanSetDifferentPoolContract() public {
        riskEngine.setPool(address(0x3828342));
        assertEq(address(riskEngine.pool()), address(0x3828342));

        vm.startPrank(address(0x21));
        vm.expectRevert();
        riskEngine.setPool(address(0x821813));
    }

    function testCanUpdateRiskModule() public {
        riskEngine.setRiskModule(address(0x3828342));
        assertEq(address(riskEngine.riskModule()), address(0x3828342));

        vm.startPrank(address(0x21));
        vm.expectRevert();
        riskEngine.setRiskModule(address(0x821813));
    }

    function testCannotUpdateLTVBeforeTimelock() public {
        vm.startPrank(address(0x99));
        riskEngine.requestLtvUpdate(linearRatePool, address(asset), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset));

        riskEngine.requestLtvUpdate(linearRatePool, address(asset), 0.50e18);

        vm.expectRevert();
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset)), 0.75e18);

        vm.warp(block.timestamp + 2 days);

        riskEngine.acceptLtvUpdate(linearRatePool, address(asset));
    }
      
}