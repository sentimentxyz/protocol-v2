// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest, MintableToken} from "../BaseTest.t.sol";
import {PortfolioLens} from "src/lens/PortfolioLens.sol";
import {FixedPriceOracle} from "src/oracle/FixedPriceOracle.sol";
import {PositionManager, Operation, Action} from "src/PositionManager.sol";
import {SingleAssetPosition} from "src/position/SingleAssetPosition.sol";

contract ScpAssetTest is BaseTest {
    PortfolioLens portfolioLens;
    SingleAssetPosition position;
    PositionManager positionManager;

    MintableToken erc201;

    function setUp() public override {
        super.setUp();

        portfolioLens = PortfolioLens(protocol.portfolioLens());
        positionManager = PositionManager(protocol.positionManager());
        position = SingleAssetPosition(_deployPosition());

        erc201 = new MintableToken();

        positionManager.toggleKnownContract(address(erc201));
    }

    function testAddAsset(uint256 amt) public {
        vm.assume(amt < MAX_NUM);
        erc201.mint(address(this), amt);
        erc201.approve(address(positionManager), type(uint256).max);

        bytes memory data = abi.encode(address(erc201), amt);
        Action memory action1 = Action({op: Operation.Deposit, data: data});
        Action memory action2 = Action({op: Operation.AddAsset, data: abi.encode(address(erc201))});
        Action[] memory actions = new Action[](2);
        actions[0] = action1;
        actions[1] = action2;

        positionManager.processBatch(address(position), actions);
        address[] memory assets = position.getAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(erc201));
    }

    function testAddAssetTwice(uint256 amt) public {
        vm.assume(amt < MAX_NUM);
        erc201.mint(address(this), amt);
        erc201.approve(address(positionManager), type(uint256).max);

        bytes memory data = abi.encode(address(erc201), amt / 2);
        Action memory action1 = Action({op: Operation.Deposit, data: data});
        Action memory action2 = Action({op: Operation.AddAsset, data: abi.encode(address(erc201))});
        Action[] memory actions = new Action[](2);
        actions[0] = action1;
        actions[1] = action2;

        positionManager.processBatch(address(position), actions);
        address[] memory assets = position.getAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(erc201));

        data = abi.encode(address(erc201), amt - (amt / 2));
        action1 = Action({op: Operation.Deposit, data: data});
        actions[0] = action1;

        positionManager.processBatch(address(position), actions);
        assertEq(erc201.balanceOf(address(position)), amt);

        assets = position.getAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(erc201));
    }

    function testRemoveAsset(uint256 amt) public {
        testAddAsset(amt);

        bytes memory data = abi.encode(address(this), address(erc201), amt);
        Action memory action1 = Action({op: Operation.Transfer, data: data});
        Action memory action2 = Action({op: Operation.RemoveAsset, data: abi.encode(address(erc201))});
        Action[] memory actions = new Action[](2);
        actions[0] = action1;
        actions[1] = action2;

        positionManager.processBatch(address(position), actions);
        address[] memory assets = position.getAssets();
        assertEq(assets.length, 0);
    }

    function testRemoveAssetTwice(uint256 amt) public {
        testRemoveAsset(amt);
        Action memory action = Action({op: Operation.RemoveAsset, data: abi.encode(address(erc201))});
        Action[] memory actions = new Action[](1);
        actions[0] = action;
        positionManager.processBatch(address(position), actions);
        address[] memory assets = position.getAssets();
        assertEq(assets.length, 0);
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
}
