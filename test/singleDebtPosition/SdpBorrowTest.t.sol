// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {Pool} from "src/Pool.sol";
import {console2} from "forge-std/Test.sol";
import {TestUtils} from "../TestUtils.sol";
import {RiskEngine} from "src/RiskEngine.sol";
import {BaseTest, MintableToken} from "../BaseTest.t.sol";
import {PortfolioLens} from "src/lens/PortfolioLens.sol";
import {FixedRateModel} from "src/irm/FixedRateModel.sol";
import {PoolFactory, PoolDeployParams} from "src/PoolFactory.sol";
import {FixedPriceOracle} from "src/oracle/FixedPriceOracle.sol";
import {SingleDebtPosition} from "src/position/SingleDebtPosition.sol";
import {SingleDebtRiskModule} from "src/risk/SingleDebtRiskModule.sol";
import {PositionManager, Operation, Action, AssetData, DebtData} from "src/PositionManager.sol";

contract SdpBorrowTest is BaseTest {
    Pool pool;
    RiskEngine riskEngine;
    PoolFactory poolFactory;
    SingleDebtPosition position;
    PortfolioLens portfolioLens;
    PositionManager positionManager;

    MintableToken erc20Collat;
    MintableToken erc20Borrow;

    function setUp() public override {
        super.setUp();
        poolFactory = PoolFactory(protocol.poolFactory());
        portfolioLens = PortfolioLens(protocol.portfolioLens());
        positionManager = PositionManager(protocol.positionManager());
        position = SingleDebtPosition(_deploySingleDebtPosition());
        riskEngine = RiskEngine(protocol.riskEngine());
        erc20Collat = new MintableToken();
        erc20Borrow = new MintableToken();

        _deployPool();

        positionManager.toggleKnownAddress(address(erc20Borrow));
    }

    function testBorrowWithinLimits() public {
        _deposit(1e18); // 1 eth
        _borrow(1e17); // 0.2 eth
        address[] memory assets = position.getAssets();
        assertEq(assets.length, 2);
        assertEq(assets[0], address(erc20Collat));
        assertEq(assets[1], address(erc20Borrow));
        assert(riskEngine.isPositionHealthy(address(position)));
        assertEq(pool.getBorrowsOf(address(position)), 1e17);
    }

    function testBorrowMultiple() public {
        _deposit(1e18);
        _borrow(1e17);
        _borrow(1e17);
        assert(riskEngine.isPositionHealthy(address(position)));
    }

    function testMaxBorrow() public {
        _deposit(1e18); // 1 eth
        _borrow(2e18 - 1); // 4eth
        address[] memory assets = position.getAssets();
        assertEq(assets.length, 2);
        assertEq(assets[0], address(erc20Collat));
        assertEq(assets[1], address(erc20Borrow));
        assert(riskEngine.isPositionHealthy(address(position)));
        assert(pool.getBorrowsOf(address(position)) == 2e18 - 1);
    }

    function testFailBorrowMoreThanLTV() public {
        _deposit(1e18); // 1 eth
        _borrow(4e18); // 8 eth
    }

    function testRepaySingle() public {
        _deposit(1e18); // 1 eth
        _borrow(1e18); // 2 eth
        _repay(1e18); // 2 eth
        assertEq(pool.getBorrowsOf(address(position)), 0);
        assertEq(position.getDebtPools().length, 0);
    }

    function testRepayMultiple() public {
        _deposit(1e18); // 1 eth
        _borrow(1e18); // 2 eth
        _repay(5e17); // 1 eth
        _repay(5e17); // 1 eth
        assertEq(pool.getBorrowsOf(address(position)), 0);
        assertEq(position.getDebtPools().length, 0);
    }

    function testMaxRepay(uint256 depositAmt, uint256 borrowAmt) public {
        vm.assume(borrowAmt > 3);
        vm.assume(depositAmt < MAX_NUM);
        // max lev is 4x and borrow asset is worth twice the collat in this case
        // so max amount of borrows is twice the absolute amount of deposit
        vm.assume(borrowAmt / 2 < depositAmt);

        _deposit(depositAmt);
        _borrow(borrowAmt);
        _repay(type(uint256).max);
    }

    function testZach_LiquidateToFalselyRepay() public {
        // starting position:
        // - deposit 100 collateral (worth 100 eth)
        // - borrow 200 borrow (worth 400 eth)
        _deposit(100e18); // 100 eth
        _borrow(200e18); // 400 eth
        assert(riskEngine.isPositionHealthy(address(position)));

        // whoops, price of collateral falls by 1%, so we're liquidatable
        FixedPriceOracle newCollatTokenOracle = new FixedPriceOracle(0.99e18);
        riskEngine.toggleOracleStatus(address(newCollatTokenOracle), address(erc20Collat));
        riskEngine.requestOracleUpdate(address(pool), address(erc20Collat), address(newCollatTokenOracle));
        riskEngine.acceptOracleUpdate(address(pool), address(erc20Collat));

        // confirm we are now unhealthy & can be liquidated
        assert(!riskEngine.isPositionHealthy(address(position)));

        // create malicious liquidation payload
        // ad[0] and dd[0] pass the check
        // dd[1] repays the full loan by using a valid pool but a malicious token
        AssetData[] memory ad = new AssetData[](1);
        ad[0] = AssetData({asset: address(erc20Collat), amt: 0});

        DebtData[] memory dd = new DebtData[](2);
        dd[0] = DebtData({pool: address(pool), asset: address(erc20Borrow), amt: 1});

        FakeToken fakeToken = new FakeToken();

        dd[1] = DebtData({pool: address(pool), asset: address(fakeToken), amt: 200e18 - 1});

        // before liquidation: 499 eth of assets vs 400 eth of debt
        (uint256 assets, uint256 debt,) = riskEngine.getRiskData(address(position));
        console2.log("Assets Before: ", assets);
        console2.log("Debt Before: ", debt);

        // liquidate (this requires having 1 wei of the token to repay)
        erc20Borrow.mint(address(this), 1);
        erc20Borrow.approve(address(positionManager), type(uint256).max);

        vm.expectRevert(SingleDebtRiskModule.SingleDebtRiskModule_InvalidDebtData.selector);
        positionManager.liquidate(address(position), dd, ad);

        // after liquidation: 499 eth of assets vs 0 debt
        (assets, debt,) = riskEngine.getRiskData(address(position));
        console2.log("Assets After: ", assets);
        console2.log("Debt After: ", debt);
    }

    function _deposit(uint256 amt) internal {
        erc20Collat.mint(address(this), amt);
        erc20Collat.approve(address(positionManager), type(uint256).max);

        bytes memory data = abi.encode(address(erc20Collat), amt);
        Action memory action1 = Action({op: Operation.Deposit, data: data});
        Action memory action2 = Action({op: Operation.AddAsset, data: abi.encode(address(erc20Collat))});
        Action[] memory actions = new Action[](2);
        actions[0] = action1;
        actions[1] = action2;

        positionManager.processBatch(address(position), actions);
    }

    function _borrow(uint256 amt) internal {
        erc20Borrow.mint(address(this), amt);
        erc20Borrow.approve(address(pool), type(uint256).max);
        pool.deposit(amt, address(this));

        bytes memory data = abi.encode(address(pool), amt);
        Action memory action = Action({op: Operation.Borrow, data: data});
        Action memory action2 = Action({op: Operation.AddAsset, data: abi.encode(address(erc20Borrow))});
        Action[] memory actions = new Action[](2);
        actions[0] = action;
        actions[1] = action2;

        positionManager.processBatch(address(position), actions);
    }

    function _deploySingleDebtPosition() internal returns (address) {
        uint256 POSITION_TYPE = 0x1;
        bytes32 salt = "SingleDebtPosition";
        bytes memory data = abi.encode(address(this), POSITION_TYPE, salt);
        (address positionAddress,) = portfolioLens.predictAddress(address(this), POSITION_TYPE, salt);

        Action memory action = Action({op: Operation.NewPosition, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.processBatch(positionAddress, actions);

        return positionAddress;
    }

    function testFailZach_RepayRoundsUp() public {
        // start the pool with sufficient tokens to borrow
        erc20Borrow.mint(address(this), 1e18);
        erc20Borrow.approve(address(pool), type(uint256).max);
        pool.deposit(1e18, address(this));

        // set up our primary user
        address user1 = makeAddr("user1");
        erc20Collat.mint(user1, 1e18);
        erc20Borrow.mint(user1, 1e18); // have extra funds to pay interest
        address user1PosAddr = _createPositionDepositAndBorrow(user1, 1e18, 1, bytes32("User1SingleDebtPosition"));

        // borrow from another user so we end up with rounding in calculations
        vm.warp(block.timestamp + 26 weeks);
        address user2 = makeAddr("user2");
        erc20Collat.mint(user2, 1e18);
        erc20Borrow.mint(user2, 1e18);
        address user2PosAddr = _createPositionDepositAndBorrow(user2, 1e18, 1, bytes32("User2SingleDebtPosition"));

        vm.warp(block.timestamp + 26 weeks);
        uint256 u1Before = pool.getBorrowsOf(address(user1PosAddr));
        uint256 u2Before = pool.getBorrowsOf(address(user2PosAddr));
        console2.log("User 1 Before: ", u1Before);
        console2.log("User 2 Before: ", u2Before);

        bytes memory data = abi.encode(address(pool), 1);
        Action memory repayAction = Action({op: Operation.Repay, data: data});
        vm.prank(user1);
        positionManager.process(address(user1PosAddr), repayAction);

        uint256 u1After = pool.getBorrowsOf(address(user1PosAddr));
        uint256 u2After = pool.getBorrowsOf(address(user2PosAddr));
        console2.log("User 1 Before: ", u1After);
        console2.log("User 2 Before: ", u2After);
    }

    function _createPositionDepositAndBorrow(address user, uint256 depAmt, uint256 borrowAmt, bytes32 salt)
        internal
        returns (address)
    {
        vm.startPrank(user);
        erc20Collat.approve(address(positionManager), type(uint256).max);
        erc20Borrow.approve(address(positionManager), type(uint256).max);

        (address positionAddr,) = portfolioLens.predictAddress(address(this), 0x1, salt);
        bytes memory newPosdata = abi.encode(user, 0x1, salt);
        Action memory newPosAction = Action({op: Operation.NewPosition, data: newPosdata});

        bytes memory depositData = abi.encode(user, address(erc20Collat), depAmt);
        Action memory depositAction = Action({op: Operation.Deposit, data: depositData});

        bytes memory borrowData = abi.encode(address(pool), borrowAmt);
        Action memory borrowAction = Action({op: Operation.Borrow, data: borrowData});

        bytes memory depositBorrowData = abi.encode(user, address(erc20Borrow), depAmt);
        Action memory depositBorrowAction = Action({op: Operation.Deposit, data: depositBorrowData});

        Action memory addAssetAction = Action({op: Operation.AddAsset, data: abi.encode(address(erc20Collat))});
        Action memory addBorrowAssetAction = Action({op: Operation.AddAsset, data: abi.encode(address(erc20Borrow))});

        Action[] memory actions = new Action[](6);
        actions[0] = newPosAction;
        actions[1] = depositAction;
        actions[2] = borrowAction;
        actions[3] = depositBorrowAction;
        actions[4] = addAssetAction;
        actions[5] = addBorrowAssetAction;

        positionManager.processBatch(positionAddr, actions);
        vm.stopPrank();

        return positionAddr;
    }

    function _deployPool() internal {
        FixedRateModel rateModel = new FixedRateModel(1e18); // 0% apr
        PoolDeployParams memory params = PoolDeployParams({
            asset: address(erc20Borrow),
            rateModel: address(rateModel),
            poolCap: type(uint256).max,
            originationFee: 0,
            name: "SDP Test Pool",
            symbol: "SDP-TEST"
        });
        pool = Pool(poolFactory.deployPool(params));

        FixedPriceOracle borrowTokenOracle = new FixedPriceOracle(2e18); // 1 borrow token = 2 eth
        riskEngine.toggleOracleStatus(address(borrowTokenOracle), address(erc20Borrow));
        riskEngine.requestOracleUpdate(address(pool), address(erc20Borrow), address(borrowTokenOracle));
        riskEngine.acceptOracleUpdate(address(pool), address(erc20Borrow));
        riskEngine.requestLtvUpdate(address(pool), address(erc20Borrow), 8e17); // max lev = 5x
        riskEngine.acceptLtvUpdate(address(pool), address(erc20Borrow)); // max lev = 5x

        FixedPriceOracle collatTokenOracle = new FixedPriceOracle(1e18); // 1 collat token = 1 eth
        riskEngine.toggleOracleStatus(address(collatTokenOracle), address(erc20Collat));
        riskEngine.requestOracleUpdate(address(pool), address(erc20Collat), address(collatTokenOracle));
        riskEngine.acceptOracleUpdate(address(pool), address(erc20Collat));
        riskEngine.requestLtvUpdate(address(pool), address(erc20Collat), 8e17); // max lev = 5x
        riskEngine.acceptLtvUpdate(address(pool), address(erc20Collat));
    }

    function _repay(uint256 amt) internal {
        bytes memory data = abi.encode(address(pool), amt);
        Action memory action = Action({op: Operation.Repay, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.processBatch(address(position), actions);
    }
}

contract FakeToken {
    function transferFrom(address, address, uint256) public pure returns (bool) {
        return true;
    }
}
