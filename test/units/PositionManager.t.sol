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

    function testInitPositionManagerFromConstructor() public {
        // registry
        registry = new Registry();

        // pool
        pool = new Pool(address(registry), address(this));

        // position manager
        positionManagerImpl = address(new PositionManager()); // deploy impl
        address beacon = address((new TransparentUpgradeableProxy(positionManagerImpl, owner, new bytes(0))));
        positionManager =
            PositionManager(beacon); // setup proxy
    

        PositionManager(positionManager).initialize(address(registry), 550);

        registry.setAddress(SENTIMENT_POSITION_BEACON_KEY, beacon);
        registry.setAddress(SENTIMENT_POOL_KEY, address(pool));
        registry.setAddress(SENTIMENT_RISK_ENGINE_KEY, address(riskEngine));

        PositionManager(positionManager).updateFromRegistry();

        assertEq(address(positionManager.pool()), address(pool));
        assertEq(address(positionManager.riskEngine()), address(riskEngine));
        assertEq(positionManager.positionBeacon(), beacon);
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

    function testInitializeIncorrectPosition() public {
        bytes32 salt = bytes32(uint256(43534853));
        bytes memory data = abi.encode(positionOwner, salt);
        Action memory action = Action({op: Operation.NewPosition, data: data});

        Action[] memory actions = new Action[](1);
        actions[0] = action;

        vm.expectRevert();
        PositionManager(positionManager).processBatch(makeAddr("incorrectPosition"), actions);
    
        vm.expectRevert();
        PositionManager(positionManager).process(makeAddr("incorrectPosition"), action);
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

    function testSimpleTransfer() public {
        testSimpleDepositCollateral(100 ether);

        vm.startPrank(positionOwner);
        bytes memory data = abi.encode(address(positionOwner), address(collateral), 50 ether);
        Action memory action = Action({op: Operation.Transfer, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        vm.expectRevert();
        PositionManager(positionManager).processBatch(position, actions);
    
        vm.expectRevert();
        PositionManager(positionManager).process(position, action);
        vm.stopPrank();

        vm.prank(positionManager.owner());
        positionManager.toggleKnownAddress(address(collateral));

        vm.startPrank(positionOwner);

        uint256 initialCollateral = collateral.balanceOf(positionOwner);
        PositionManager(positionManager).processBatch(position, actions);
        assertEq(collateral.balanceOf(positionOwner), initialCollateral + 50 ether);
    
        initialCollateral = collateral.balanceOf(positionOwner);
        PositionManager(positionManager).process(position, action);
        assertEq(collateral.balanceOf(positionOwner), initialCollateral + 50 ether);
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

    function testCannotBorrowFromDeadPool() public {
        testSimpleDepositCollateral(100 ether);

        address rateModel = address(new LinearRateModel(1e18, 2e18));
        uint256 corruptPool = pool.initializePool(address(0), address(asset), rateModel, 0, 0);

        vm.startPrank(positionOwner);
        bytes memory data = abi.encode(corruptPool, 2 ether);

        Action memory action = Action({op: Operation.Borrow, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        vm.expectRevert();
        PositionManager(positionManager).processBatch(position, actions);
    }

    function testSimpleRepay() public {
        testSimpleBorrow();

        vm.startPrank(positionOwner);
        bytes memory data = abi.encode(linearRatePool, 1 ether);

        Action memory action = Action({op: Operation.Repay, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        (,,,,,, Pool.Uint128Pair memory totalBorrows) = pool.poolDataFor(linearRatePool);
        uint256 initialBorrow = pool.getBorrowsOf(linearRatePool, position);

        PositionManager(positionManager).processBatch(position, actions);

        (,,,,,, Pool.Uint128Pair memory newTotalBorrows) = pool.poolDataFor(linearRatePool);

        uint256 borrow = pool.getBorrowsOf(linearRatePool, position);

        assertLt(borrow, initialBorrow);
        assertLt(newTotalBorrows.assets, totalBorrows.assets);
    }

    function testFullRepay() public {
        testSimpleBorrow();

        uint256 borrow = pool.getBorrowsOf(linearRatePool, position);

        vm.startPrank(positionOwner);
        bytes memory data = abi.encode(linearRatePool, borrow);

        asset.mint(position, 5 ether);

        Action memory action = Action({op: Operation.Repay, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        assertEq(Position(position).getDebtPools().length, 1);

        PositionManager(positionManager).processBatch(position, actions);

        assertEq(Position(position).getDebtPools().length, 0);
    }

    function testSimpleExec() public {
        TestCallContract testContract = new TestCallContract(false);

        bytes memory data = abi.encodePacked(address(testContract), bytes4(keccak256("testCall()")));
        Action memory action = Action({op: Operation.Exec, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        vm.prank(positionManager.owner());
        positionManager.toggleKnownAddress(address(testContract));
        vm.prank(positionManager.owner());
        positionManager.toggleKnownFunc(address(testContract), bytes4(keccak256("testCall()")));

        assertEq(testContract.ping(), 0);

        vm.startPrank(positionOwner);

        PositionManager(positionManager).processBatch(position, actions);

        assertEq(testContract.ping(), 1);
    }


    function testSimpleFailedCall() public {
        TestCallContract testContract = new TestCallContract(true);

        bytes memory data = abi.encodePacked(address(testContract), bytes4(keccak256("testCall()")));
        Action memory action = Action({op: Operation.Exec, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        vm.prank(positionManager.owner());
        positionManager.toggleKnownAddress(address(testContract));
        vm.prank(positionManager.owner());
        positionManager.toggleKnownFunc(address(testContract), bytes4(keccak256("testCall()")));

        assertEq(testContract.ping(), 0);

        vm.startPrank(positionOwner);

        vm.expectRevert();
        PositionManager(positionManager).process(position, action);

        assertEq(testContract.ping(), 0);
    }

    function testExecNegativeCases() public {
        TestCallContract testContract = new TestCallContract(false);

        bytes memory data = abi.encodePacked(address(testContract), bytes4(keccak256("testCall()")));
        Action memory action = Action({op: Operation.Exec, data: data});

        vm.startPrank(positionOwner);
        vm.expectRevert();
        PositionManager(positionManager).process(position, action);
        vm.stopPrank();

        vm.prank(positionManager.owner());
        positionManager.toggleKnownAddress(address(testContract));

        assertEq(testContract.ping(), 0);

        vm.startPrank(positionOwner);
        vm.expectRevert();
        PositionManager(positionManager).process(position, action);
        vm.stopPrank();

        vm.prank(positionManager.owner());
        positionManager.toggleKnownFunc(address(testContract), bytes4(keccak256("testCall()")));

        assertEq(testContract.ping(), 0);

        vm.startPrank(positionOwner);
        PositionManager(positionManager).process(position, action);
        vm.stopPrank();

        assertEq(testContract.ping(), 1);
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

    function testApproveAction() public {
        testSimpleDepositCollateral(100 ether);

        address spender = makeAddr("spender");

        vm.startPrank(positionOwner);
        bytes memory data = abi.encode(spender, address(collateral), 100 ether);
        Action memory action = Action({op: Operation.Approve, data: data});

        vm.expectRevert();
        PositionManager(positionManager).process(position, action);
        vm.stopPrank();

        vm.prank(positionManager.owner());
        positionManager.toggleKnownAddress(address(collateral));

        vm.startPrank(positionOwner);
        vm.expectRevert();
        PositionManager(positionManager).process(position, action);
        vm.stopPrank();

        vm.prank(positionManager.owner());
        positionManager.toggleKnownAddress(spender);

        vm.prank(positionOwner);
        PositionManager(positionManager).process(position, action);

        vm.prank(spender);
        collateral.transferFrom(address(position), address(spender), 100 ether);    
    }

    function testToggleAuth() public {
        vm.startPrank(positionOwner);
        bytes memory data = abi.encode(address(collateral));
        Action memory action = Action({op: Operation.AddToken, data: data});

        PositionManager(positionManager).process(position, action);

        address newOwner = makeAddr("newOwner");
        vm.stopPrank();

        vm.startPrank(newOwner);
        data = abi.encode(address(asset));
        action = Action({op: Operation.AddToken, data: data});

        vm.expectRevert();
        PositionManager(positionManager).process(position, action);
        vm.stopPrank();

        vm.startPrank(makeAddr("aRandomGuy"));
        vm.expectRevert();
        positionManager.toggleAuth(newOwner, position);
        vm.stopPrank();

        vm.prank(positionOwner);
        positionManager.toggleAuth(newOwner, position);

        vm.prank(newOwner);
        PositionManager(positionManager).process(position, action);
    }

    function testNoInsolventActions() public {
        testSimpleDepositCollateral(1 ether);

        vm.startPrank(positionOwner);
        bytes memory data = abi.encode(linearRatePool, 1000 ether);
        Action memory action = Action({op: Operation.Borrow, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        vm.expectRevert();
        PositionManager(positionManager).processBatch(position, actions);
    
        vm.expectRevert();
        PositionManager(positionManager).process(position, action);
    }
}


contract TestCallContract {
    bool immutable revertOrNot;
    uint256 public ping;

    constructor(bool _revertOrNot) {
        revertOrNot = _revertOrNot;
    }

    function testCall() public {
        if (revertOrNot) {
            revert("Call Revert");
        }
        ping++;
    }
}

