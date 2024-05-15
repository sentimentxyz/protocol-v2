// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseTest.t.sol";

import {FixedRateModel} from "../../src/irm/FixedRateModel.sol";
import {LinearRateModel} from "../../src/irm/LinearRateModel.sol";

import {Action, Operation} from "src/PositionManager.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {FixedPriceOracle} from "src/oracle/FixedPriceOracle.sol";

contract PoolUnitTests is BaseTest {
    address public positionOwner = makeAddr("positionOwner");
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

        bytes32 salt = bytes32(uint256(3492932942));
        bytes memory data = abi.encode(positionOwner, salt);

        (position,) = portfolioLens.predictAddress(positionOwner, salt);

        Action memory action = Action({op: Operation.NewPosition, data: data});

        Action[] memory actions = new Action[](1);
        actions[0] = action;

        PositionManager(positionManager).processBatch(position, actions);

        vm.startPrank(protocolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset));

        riskEngine.requestLtvUpdate(linearRatePool, address(collateral), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(collateral));
        vm.stopPrank();
    }

    function testInitNewPositionRaw() public {
        address pool2 = makeAddr("pool2");
        address positionManager2 = makeAddr("positionManager2");

        Position newPosition = new Position(pool2, positionManager2);

        assertEq(address(newPosition.POOL()), pool2);
        assertEq(address(newPosition.POSITION_MANAGER()), positionManager2);
    }

    function testCannotCallNonAuthorizedFunctions() public {
        address hacker = makeAddr("hacker");
        vm.startPrank(hacker);
        
        vm.expectRevert();
        Position(position).approve(address(collateral), hacker, 10000 ether);

        // So the call doesn't revert for a lack of balance
        collateral.mint(address(position), 10000 ether);

        vm.expectRevert();
        Position(position).transfer(address(collateral), hacker, 10000 ether);

        vm.expectRevert();
        Position(position).borrow(linearRatePool, 10000 ether);

        vm.expectRevert();
        Position(position).repay(linearRatePool, 10000 ether);

        vm.expectRevert();
        Position(position).addCollateralType(address(collateral));

        vm.expectRevert();
        Position(position).removeCollateralType(address(collateral));

        vm.expectRevert();
        Position(position).exec(address(0x0), bytes(""));
    }

    function testCannotExceedPoolMaxLength() public {
        vm.startPrank(address(positionManager));

        for (uint256 i = 1; i < 6; i++) {
            Position(position).addCollateralType(address(vm.addr(i)));
        }

        vm.expectRevert();
        Position(position).addCollateralType(address(vm.addr(6)));

        for (uint256 i = 1; i < 6; i++) {
            Position(position).borrow(i, 10000 ether);
        }

        vm.expectRevert();
        Position(position).borrow(6, 10000 ether);
    }
}
