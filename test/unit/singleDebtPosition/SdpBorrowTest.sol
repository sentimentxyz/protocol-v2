// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Pool} from "src/Pool.sol";
import {TestUtils} from "../../Utils.sol";
import {RiskEngine} from "src/RiskEngine.sol";
import {BaseTest, MintableToken} from "../BaseTest.sol";
import {PortfolioLens} from "src/lens/PortfolioLens.sol";
import {FixedRateModel} from "src/irm/FixedRateModel.sol";
import {PoolFactory, PoolDeployParams} from "src/PoolFactory.sol";
import {FixedPriceOracle} from "src/oracle/FixedPriceOracle.sol";
import {SingleDebtPosition} from "src/positions/SingleDebtPosition.sol";
import {PositionManager, Operation, Action} from "src/PositionManager.sol";

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
        poolFactory = deploy.poolFactory();
        portfolioLens = deploy.portfolioLens();
        positionManager = deploy.positionManager();
        position = SingleDebtPosition(_deploySingleDebtPosition());
        riskEngine = deploy.riskEngine();
        erc20Collat = new MintableToken();
        erc20Borrow = new MintableToken();

        _deployPool();

        positionManager.toggleKnownContract(address(erc20Borrow));
    }

    function testBorrowWithinLimits() public {
        _deposit(1e18); // 1 eth
        _borrow(1e17); // 0.2 eth
        address[] memory assets = position.getAssets();
        assertEq(assets.length, 2);
        assertEq(assets[0], address(erc20Collat));
        assertEq(assets[1], address(erc20Borrow));
        assert(riskEngine.isPositionHealthy(address(position)));
        assert(pool.getBorrowsOf(address(position)) == 1e17);
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

    function _deposit(uint256 amt) internal {
        erc20Collat.mint(address(this), amt);
        erc20Collat.approve(address(positionManager), type(uint256).max);

        bytes memory data = abi.encode(address(erc20Collat), amt);
        Action memory action1 = Action({op: Operation.Deposit, target: address(this), data: data});
        Action memory action2 = Action({op: Operation.AddAsset, target: address(erc20Collat), data: new bytes(0)});
        Action[] memory actions = new Action[](2);
        actions[0] = action1;
        actions[1] = action2;

        positionManager.process(address(position), actions);
    }

    function _borrow(uint256 amt) internal {
        erc20Borrow.mint(address(this), amt);
        erc20Borrow.approve(address(pool), type(uint256).max);
        pool.deposit(amt, address(this));

        bytes memory data = abi.encode(amt);
        Action memory action = Action({op: Operation.Borrow, target: address(pool), data: data});
        Action memory action2 = Action({op: Operation.AddAsset, target: address(erc20Borrow), data: new bytes(0)});
        Action[] memory actions = new Action[](2);
        actions[0] = action;
        actions[1] = action2;

        positionManager.process(address(position), actions);
    }

    function _deploySingleDebtPosition() internal returns (address) {
        uint256 POSITION_TYPE = 0x1;
        bytes32 salt = "SingleDebtPosition";
        bytes memory data = abi.encode(POSITION_TYPE, salt);
        address positionAddress = portfolioLens.predictAddress(POSITION_TYPE, salt);

        Action memory action = Action({op: Operation.NewPosition, target: address(this), data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.process(positionAddress, actions);

        return positionAddress;
    }

    function _deployPool() internal {
        pool = new Pool(address(positionManager));
        pool = Pool(payable(address(TestUtils.makeProxy(address(pool), address(this)))));
        pool.initialize(address(erc20Borrow), "SDP Test Pool", "SDP-TEST");
        FixedRateModel rateModel = new FixedRateModel(0); // 0% apr
        pool.setRateModel(address(rateModel));
        pool.setPoolCap(type(uint256).max);

        FixedPriceOracle borrowTokenOracle = new FixedPriceOracle(2e18); // 1 borrow token = 2 eth
        riskEngine.toggleOracleStatus(address(borrowTokenOracle));
        riskEngine.setOracle(address(pool), address(erc20Borrow), address(borrowTokenOracle));
        riskEngine.setLtv(address(pool), address(erc20Borrow), 4e18); // 400% ltv

        FixedPriceOracle collatTokenOracle = new FixedPriceOracle(1e18); // 1 collat token = 1 eth
        riskEngine.toggleOracleStatus(address(collatTokenOracle));
        riskEngine.setOracle(address(pool), address(erc20Collat), address(collatTokenOracle));
        riskEngine.setLtv(address(pool), address(erc20Collat), 4e18); // 400% ltv
    }
}
