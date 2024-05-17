// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseTest.t.sol";
import {RiskEngine} from "src/RiskEngine.sol";
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

    function testRiskEngineInit() public {
        RiskEngine testRiskEngine = new RiskEngine(address(registry), 0, 1e18);
        assertEq(address(testRiskEngine.registry()), address(registry));
        assertEq(testRiskEngine.minLtv(), uint256(0));
        assertEq(testRiskEngine.maxLtv(), uint256(1e18));
    }

    function testNoOracleFound(address asset) public {
        vm.assume(asset != address(asset1) && asset != address(asset2));
        vm.expectRevert(abi.encodeWithSelector(RiskEngine.RiskEngine_NoOracleFound.selector, asset));
        riskEngine.getOracleFor(asset);
    }

    function testOwnerCanUpdateLTV() public {
        uint256 startLtv = riskEngine.ltvFor(linearRatePool, address(asset1));
        assertEq(startLtv, 0);

        vm.startPrank(poolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.75e18);

        riskEngine.acceptLtvUpdate(linearRatePool, address(asset1));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset1)), 0.75e18);
    }

    function testOnlyOwnerCanUpdateLTV(address sender) public {
        vm.assume(sender != poolOwner);

        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(RiskEngine.RiskEngine_OnlyPoolOwner.selector, linearRatePool, sender));
        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.75e18);
    }

    function testCannotUpdateLTVForUnknownAsset(address asset, uint256 ltv) public {
        vm.assume(asset != address(asset1) && asset != address(asset2));

        vm.prank(poolOwner);
        vm.expectRevert(abi.encodeWithSelector(RiskEngine.RiskEngine_NoOracleFound.selector, asset));
        riskEngine.requestLtvUpdate(linearRatePool, asset, ltv);
    }

    function testOwnerCanRejectLTVUpdated() public {
        // Set a starting non-zero ltv
        vm.startPrank(poolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset1));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset1)), 0.75e18);

        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.5e18);
        riskEngine.rejectLtvUpdate(linearRatePool, address(asset1));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset1)), 0.75e18);
    }

    function testNoLTVUpdate(address asset) public {
        vm.prank(poolOwner);
        vm.expectRevert(abi.encodeWithSelector(RiskEngine.RiskEngine_NoLtvUpdate.selector, linearRatePool, asset));
        riskEngine.acceptLtvUpdate(linearRatePool, asset);
    }

    function testNonOwnerCannotUpdateLTV() public {
        vm.prank(poolOwner);
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

        vm.startPrank(poolOwner);
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
        vm.startPrank(poolOwner);
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
