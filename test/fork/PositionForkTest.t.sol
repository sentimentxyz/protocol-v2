// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MockERC20 } from "../mocks/MockERC20.sol";
import { ActionUtils } from "../utils/ActionUtils.sol";
import { BaseForkTest } from "./BaseForkTest.t.sol";
import { Pool } from "src/Pool.sol";
import { Position } from "src/Position.sol";
import { PositionManager } from "src/PositionManager.sol";
import { Action } from "src/PositionManager.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { PortfolioLens } from "src/lens/PortfolioLens.sol";

contract PositionForkTest is BaseForkTest {
    function setUp() public override {
        super.setUp();
    }

    function testForkCreateNewPosition() public {
        Position position = _createNewPosition();

        assertEq(position.VERSION(), 1);
        assertEq(position.MAX_ASSETS(), 5);
        assertEq(position.MAX_DEBT_POOLS(), 5);
        assertEq(address(position.POOL()), address(pool));
        assertTrue(riskEngine.isPositionHealthy(payable(position)));
        assertEq(positionManager.ownerOf(address(position)), sender);
        assertEq(position.POSITION_MANAGER(), address(positionManager));

        (uint256 totalAssetValue, uint256 totalDebtValue, uint256 minReqAssetValue) =
            riskEngine.getRiskData(payable(position));
        assertEq(totalAssetValue, 0);
        assertEq(totalDebtValue, 0);
        assertEq(minReqAssetValue, 0);

        uint256[] memory debtPools = position.getDebtPools();
        assertEq(debtPools.length, 0);

        address[] memory positionAssets = position.getPositionAssets();
        assertEq(positionAssets.length, 0);
    }

    function testForkDepositUsdc() public {
        _depositAssets("$.usdc", 100e6);
    }

    function testForkDepositWeth() public {
        _depositAssets("$.weth", 10e18);
    }

    function _getValueInEth(address asset, uint256 amt) internal view returns (uint256) {
        IOracle oracle = IOracle(riskEngine.getOracleFor(asset));
        return oracle.getValueInEth(asset, amt);
    }

    function _createNewPosition() internal returns (Position position) {
        pool = Pool(vm.parseJsonAddress(config, "$.pool"));
        sender = vm.parseJsonAddress(config, "$.sender");
        riskEngine = RiskEngine(vm.parseJsonAddress(config, "$.riskEngine"));
        portfolioLens = PortfolioLens(vm.parseJsonAddress(config, "$.portfolioLens"));
        positionManager = PositionManager(vm.parseJsonAddress(config, "$.positionManager"));

        bytes32 salt = bytes32(block.timestamp);
        (address payable predictedPosition, bool isAvailable) = portfolioLens.predictAddress(sender, salt);
        assertTrue(isAvailable);

        Action[] memory actions = new Action[](1);
        actions[0] = ActionUtils.newPosition(sender, salt);
        vm.prank(sender);
        positionManager.processBatch(predictedPosition, actions);

        return Position(predictedPosition);
    }

    function _depositAssets(string memory key, uint256 amt) internal {
        address asset = vm.parseJsonAddress(config, key);

        Position position = _createNewPosition(); // config is loaded here, don't use above
        Action[] memory actions = new Action[](2);
        actions[0] = ActionUtils.deposit(asset, amt);
        actions[1] = ActionUtils.addToken(asset);

        MockERC20(asset).mint(sender, amt);

        vm.startPrank(sender);
        MockERC20(asset).approve(address(positionManager), amt);
        positionManager.processBatch(payable(position), actions);
        vm.stopPrank();

        uint256[] memory debtPools = position.getDebtPools();
        assertEq(debtPools.length, 0);

        address[] memory positionAssets = position.getPositionAssets();
        assertEq(positionAssets.length, 1);
        assertEq(positionAssets[0], asset);

        assertEq(MockERC20(asset).balanceOf(address(position)), amt);
        assertTrue(riskEngine.isPositionHealthy(payable(position)));

        (uint256 totalAssetValue, uint256 totalDebtValue, uint256 minReqAssetValue) =
            riskEngine.getRiskData(payable(position));
        assertEq(totalAssetValue, _getValueInEth(asset, amt));
        assertEq(totalDebtValue, 0);
        assertEq(minReqAssetValue, 0);
    }
}
