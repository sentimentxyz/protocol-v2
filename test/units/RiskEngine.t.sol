// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseTest.t.sol";
import {FixedRateModel} from "../../src/irm/FixedRateModel.sol";
import {LinearRateModel} from "../../src/irm/LinearRateModel.sol";

import {Action, Operation} from "src/PositionManager.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {FixedPriceOracle} from "src/oracle/FixedPriceOracle.sol";

contract RiskModuleUnitTests is BaseTest {
    address public position;
    address public positionOwner = makeAddr("positionOwner");
    FixedPriceOracle asset1Oracle = new FixedPriceOracle(10e18);
    FixedPriceOracle asset2Oracle = new FixedPriceOracle(0.5e18);

    function setUp() public override {
        super.setUp();

        vm.startPrank(protocolOwner);
        riskEngine.setOracle(address(asset1), address(asset1Oracle));
        riskEngine.setOracle(address(asset2), address(asset2Oracle));
        vm.stopPrank();

        asset1.mint(address(this), 10000 ether);
        asset1.approve(address(pool), 10000 ether);

        pool.deposit(linearRatePool, 10000 ether, address(0x9));
    }

    function testOwnerCanUpdateLTV() public {
        uint256 startLtv = riskEngine.ltvFor(linearRatePool, address(asset1));
        assertEq(startLtv, 0);

        vm.startPrank(protocolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.75e18);

        riskEngine.acceptLtvUpdate(linearRatePool, address(asset1));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset1)), 0.75e18);
    }

    function testOwnerCanRejectLTVUpdated() public {
        // Set a starting non-zero ltv
        vm.startPrank(protocolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset1));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset1)), 0.75e18);

        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.5e18);
        riskEngine.rejectLtvUpdate(linearRatePool, address(asset1));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset1)), 0.75e18);
    }

    function testNonOwnerCannotUpdateLTV() public {
        vm.prank(protocolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.75e18);

        vm.startPrank(makeAddr("notOwner"));
        vm.expectRevert();
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset1));

        vm.expectRevert();
        riskEngine.rejectLtvUpdate(linearRatePool, address(asset1));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset1)), 0);
    }

    function testCannotSetLTVOutsideGlobalLimits() public {
        vm.prank(riskEngine.owner());
        riskEngine.setLtvBounds(0.25e18, 1.25e18);

        vm.startPrank(protocolOwner);
        vm.expectRevert();
        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.24e18);

        vm.expectRevert();
        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 1.26e18);

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset1)), 0);
    }

    function testCanUpdateRiskModule() public {
        vm.prank(protocolOwner);
        riskEngine.setRiskModule(address(0x3828342));
        assertEq(address(riskEngine.riskModule()), address(0x3828342));

        vm.startPrank(address(0x21));
        vm.expectRevert();
        riskEngine.setRiskModule(address(0x821813));
    }

    function testCannotUpdateLTVBeforeTimelock() public {
        vm.startPrank(protocolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset1));

        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.5e18);

        vm.expectRevert();
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset1));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset1)), 0.75e18);

        vm.warp(block.timestamp + 2 days);

        riskEngine.acceptLtvUpdate(linearRatePool, address(asset1));
    }
}
