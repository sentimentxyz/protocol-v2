// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Pool} from "src/Pool.sol";
import {TestUtils} from "../TestUtils.sol";
import {RiskEngine} from "src/RiskEngine.sol";
import {BaseTest, MintableToken} from "../BaseTest.t.sol";
import {PortfolioLens} from "src/lens/PortfolioLens.sol";
import {FixedRateModel} from "src/irm/FixedRateModel.sol";
import {PoolFactory, PoolDeployParams} from "src/PoolFactory.sol";
import {FixedPriceOracle} from "src/oracle/FixedPriceOracle.sol";
import {SingleAssetPosition} from "src/position/SingleAssetPosition.sol";
import {PositionManager, Operation, Action} from "src/PositionManager.sol";

contract ScpBorrowTest is BaseTest {
    Pool pool;
    RiskEngine riskEngine;
    PoolFactory poolFactory;
    SingleAssetPosition position;
    PortfolioLens portfolioLens;
    PositionManager positionManager;

    MintableToken erc20Collat;

    function setUp() public override {
        super.setUp();
        poolFactory = PoolFactory(protocol.poolFactory());
        portfolioLens = PortfolioLens(protocol.portfolioLens());
        positionManager = PositionManager(protocol.positionManager());
        position = SingleAssetPosition(_deployPosition());
        riskEngine = RiskEngine(protocol.riskEngine());
        erc20Collat = new MintableToken();

        _deployPool();

        positionManager.toggleKnownContract(address(erc20Collat));
    }

    function testBorrowWithinLimits() public {
        _deposit(1e18); // 1 eth
        _borrow(1e17); // 0.2 eth
        address[] memory assets = position.getAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(erc20Collat));
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
        _borrow(4e18); // 4eth
        address[] memory assets = position.getAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(erc20Collat));
        assert(riskEngine.isPositionHealthy(address(position)));
        assert(pool.getBorrowsOf(address(position)) == 4e18);
    }

    function testFailBorrowMoreThanLTV() public {
        _deposit(1e18); // 1 eth
        _borrow(4e18 + 1); // 8 eth + 1
    }

    function testRepaySingle() public {
        _deposit(1e18); // 1 eth
        _borrow(1e18); // 2 eth
        _repay(1e18); // 2 eth
        assertEq(pool.getBorrowsOf(address(position)), 0);
        address[] memory debtPools = position.getDebtPools();
        assertEq(debtPools.length, 0);
    }

    function testRepayMultiple() public {
        _deposit(1e18); // 1 eth
        _borrow(1e18); // 2 eth
        _repay(5e17); // 1 eth
        _repay(5e17); // 1 eth
        assertEq(pool.getBorrowsOf(address(position)), 0);
        address[] memory debtPools = position.getDebtPools();
        assertEq(debtPools.length, 0);
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
        erc20Collat.mint(address(this), amt);
        erc20Collat.approve(address(pool), type(uint256).max);
        pool.deposit(amt, address(this));

        bytes memory data = abi.encode(address(pool), amt);
        Action memory action = Action({op: Operation.Borrow, data: data});
        Action memory action2 = Action({op: Operation.AddAsset, data: abi.encode(address(erc20Collat))});
        Action[] memory actions = new Action[](2);
        actions[0] = action;
        actions[1] = action2;

        positionManager.processBatch(address(position), actions);
    }

    function _repay(uint256 amt) internal {
        bytes memory data = abi.encode(address(pool), amt);
        Action memory action = Action({op: Operation.Repay, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.processBatch(address(position), actions);
    }

    function _deployPosition() internal returns (address) {
        uint256 POSITION_TYPE = 0x2;
        bytes32 salt = "SingleAssetPosition";
        bytes memory data = abi.encode(address(this), POSITION_TYPE, salt);
        (address positionAddress,) = portfolioLens.predictAddress(POSITION_TYPE, salt);

        Action memory action = Action({op: Operation.NewPosition, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.processBatch(positionAddress, actions);

        return positionAddress;
    }

    function _deployPool() internal {
        FixedRateModel rateModel = new FixedRateModel(0); // 0% apr
        PoolDeployParams memory params = PoolDeployParams({
            asset: address(erc20Collat),
            rateModel: address(rateModel),
            poolCap: type(uint256).max,
            originationFee: 0,
            name: "SDP Test Pool",
            symbol: "SDP-TEST"
        });
        pool = Pool(poolFactory.deployPool(params));

        FixedPriceOracle collatTokenOracle = new FixedPriceOracle(1e18); // 1 collat token = 1 eth
        riskEngine.toggleOracleStatus(address(collatTokenOracle), address(erc20Collat));
        riskEngine.setOracle(address(pool), address(erc20Collat), address(collatTokenOracle));
        riskEngine.setLtv(address(pool), address(erc20Collat), 4e18); // 400% ltv
    }

    function testFailZach_DepositFrontrun() public {
        // a user with 1e18 tokens
        address user = makeAddr("user");
        erc20Collat.mint(user, 1e18);

        // user approves the position manager in advance of depositing them
        vm.prank(user);
        erc20Collat.approve(address(positionManager), 1e18);

        // an attacker can jump in and steal the tokens for their own position
        address attacker = makeAddr("attacker");
        vm.startPrank(attacker);

        uint256 POSITION_TYPE = 0x2;
        bytes32 salt = "AttackerSingleAssetPosition";
        SingleAssetPosition attackerPosition = SingleAssetPosition(portfolioLens.predictAddress(POSITION_TYPE, salt));
        bytes memory newPosData = abi.encode(attacker, POSITION_TYPE, salt);
        Action memory newPosAction = Action({op: Operation.NewPosition, data: newPosData});

        bytes memory depositData = abi.encode(user, address(erc20Collat), 1e18);
        Action memory depositAction = Action({op: Operation.Deposit, data: depositData});

        Action[] memory actions = new Action[](2);
        actions[0] = newPosAction;
        actions[1] = depositAction;

        positionManager.processBatch(address(attackerPosition), actions);

        // now the attacker has the user funds
        assertEq(erc20Collat.balanceOf(address(attackerPosition)), 1e18);
        assertEq(erc20Collat.balanceOf(user), 0);
    }
}
