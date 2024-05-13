// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseTest.t.sol";
import {FixedRateModel} from "../../src/irm/FixedRateModel.sol";
import {LinearRateModel} from "../../src/irm/LinearRateModel.sol";

import {Action, Operation} from "src/PositionManager.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {FixedPriceOracle} from "src/oracle/FixedPriceOracle.sol";

contract PositionManagerUnitTests is BaseTest {
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
        // owner = address(0x05);

        (position,) = portfolioLens.predictAddress(positionOwner, salt);

        Action memory action = Action({op: Operation.NewPosition, data: data});

        Action[] memory actions = new Action[](1);
        actions[0] = action;

        PositionManager(positionManager).processBatch(position, actions);

        vm.startPrank(protocolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset));
        vm.stopPrank();
    }

    function testInitializePosition() public {
        bytes32 salt = bytes32(uint256(43534853));
        bytes memory data = abi.encode(positionOwner, salt);
        // owner = address(0x05);

        (address expectedAddress,) = portfolioLens.predictAddress(positionOwner, salt);

        Action memory action = Action({op: Operation.NewPosition, data: data});

        Action[] memory actions = new Action[](1);
        actions[0] = action;

        PositionManager(positionManager).processBatch(expectedAddress, actions);

        uint32 size;
        assembly {
            size := extcodesize(expectedAddress)
        }

        assertGt(size, 0);
    }

    /* function testAddAndRemoveCollateralTypes() public {
        vm.startPrank(owner);
        bytes memory data = abi.encode(address(collateral));
        Action memory action = Action({op: Operation.AddCollateralType, data: data});

        Action[] memory actions = new Action[](1);
        actions[0] = action;

        PositionManager(positionManager).processBatch(position, actions);

        Action memory action2 = Action({op: Operation.RemoveCollateralType, data: data});

        Action[] memory actions2 = new Action[](1);
        actions2[0] = action2;

        PositionManager(positionManager).processBatch(position, actions2);
    } */

    function testSimpleBorrow() public {
        address user = makeAddr("user");
        vm.startPrank(user);

        collateral.mint(user, 1000 ether);
    }
}
