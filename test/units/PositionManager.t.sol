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

    function testInitializePosition() public {
        bytes32 salt = bytes32(uint256(43534853));
        bytes memory data = abi.encode(positionOwner, salt);

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

    function testAddAndRemoveCollateralTypes() public {
        vm.startPrank(positionOwner);
        bytes memory data = abi.encode(address(collateral));
        Action memory action = Action({op: Operation.AddToken, data: data});

        Action[] memory actions = new Action[](1);
        actions[0] = action;

        PositionManager(positionManager).processBatch(position, actions);

        assertEq(Position(position).getPositionAssets().length, 1);
        assertEq(Position(position).getPositionAssets()[0], address(collateral));

        Action memory action2 = Action({op: Operation.RemoveToken, data: data});

        Action[] memory actions2 = new Action[](1);
        actions2[0] = action2;

        PositionManager(positionManager).processBatch(position, actions2);
        assertEq(Position(position).getPositionAssets().length, 0);
    } 

    function testSimpleDepositCollateral(uint96 amount) public {
        vm.startPrank(positionOwner);
        bytes memory data = abi.encode(address(collateral));
        Action memory action = Action({op: Operation.AddToken, data: data});

        Action[] memory actions = new Action[](1);
        actions[0] = action;

        PositionManager(positionManager).processBatch(position, actions);

        data = abi.encode(address(collateral), amount);

        actions[0] = Action({op: Operation.Deposit, data: data});

        collateral.mint(positionOwner, amount);
        collateral.approve(address(positionManager), amount);

        PositionManager(positionManager).processBatch(position, actions);
        
        assertEq(collateral.balanceOf(address(position)), amount);
        vm.stopPrank();
    }

    function testSimpleBorrow() public {
        testSimpleDepositCollateral(100 ether);

        vm.startPrank(positionOwner);
        bytes memory data = abi.encode(linearRatePool, 2 ether);

        Action memory action = Action({op: Operation.Borrow, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        uint256 initialAssetBalance = asset.balanceOf(position);
        (,,,,,, Pool.Uint128Pair memory totalBorrows) = pool.poolDataFor(linearRatePool);
        assertEq(address(positionManager.pool()), address(pool));

        PositionManager(positionManager).processBatch(position, actions);

        assertGt(asset.balanceOf(position), initialAssetBalance);
        (,,,,,, Pool.Uint128Pair memory newTotalBorrows) = pool.poolDataFor(linearRatePool);
        assertEq(newTotalBorrows.assets, totalBorrows.assets + 2 ether);
    }

    // Test setting the beacon address
    function testSetBeacon() public {
        address newBeacon = makeAddr("newBeacon");
        vm.prank(positionManager.owner());
        positionManager.setBeacon(newBeacon);
        assertEq(positionManager.positionBeacon(), newBeacon, "Beacon address should be updated");

        vm.startPrank(makeAddr("nonOwner")); // Non-owner address
        vm.expectRevert();
        positionManager.setBeacon(newBeacon);
    }

    // Test setting the risk engine address
    function testSetRiskEngine() public {
        address newRiskEngine = makeAddr("newRiskEngine");
        vm.prank(positionManager.owner());
        positionManager.setRiskEngine(newRiskEngine);
        assertEq(address(positionManager.riskEngine()), newRiskEngine, "Risk engine address should be updated");

        vm.startPrank(makeAddr("nonOwner")); // Non-owner address
        vm.expectRevert();
        positionManager.setRiskEngine(newRiskEngine);
    }

    // Test setting the liquidation fee
    function testSetLiquidationFee() public {
        uint256 newFee = 100; // Example fee
        vm.prank(positionManager.owner());
        positionManager.setLiquidationFee(newFee);
        assertEq(positionManager.liquidationFee(), newFee, "Liquidation fee should be updated");

        vm.startPrank(makeAddr("nonOwner")); // Non-owner address
        vm.expectRevert();
        positionManager.setLiquidationFee(newFee);
    }

    // Test toggling known address
    function testToggleKnownAddress() public {
        address target = makeAddr("target");
        bool initialState = positionManager.isKnownAddress(target);

        vm.prank(positionManager.owner());
        positionManager.toggleKnownAddress(target);
        assertEq(positionManager.isKnownAddress(target), !initialState, "Known address state should be toggled");

        vm.startPrank(makeAddr("nonOwner")); // Non-owner address
        vm.expectRevert();
        positionManager.toggleKnownAddress(target);
    }

    // Test toggling known function
    function testToggleKnownFunc() public {
        address target = makeAddr("target");
        bytes4 method = bytes4(keccak256("testMethod()"));
        bool initialState = positionManager.isKnownFunc(target, method);

        vm.prank(positionManager.owner());
        positionManager.toggleKnownFunc(target, method);
        assertEq(positionManager.isKnownFunc(target, method), !initialState, "Known function state should be toggled");

        vm.startPrank(makeAddr("nonOwner")); // Non-owner address
        vm.expectRevert();
        positionManager.toggleKnownFunc(target, method);
    }
}
