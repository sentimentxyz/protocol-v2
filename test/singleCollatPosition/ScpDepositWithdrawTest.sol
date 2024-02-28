// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest, MintableToken} from "../BaseTest.sol";
import {PortfolioLens} from "src/lens/PortfolioLens.sol";
import {SingleAssetPosition} from "src/position/SingleAssetPosition.sol";
import {PositionManager, Operation, Action} from "src/PositionManager.sol";

contract ScpDepositWithdrawTest is BaseTest {
    SingleAssetPosition position;
    PortfolioLens portfolioLens;
    PositionManager positionManager;

    MintableToken erc201;

    function setUp() public override {
        super.setUp();
        portfolioLens = deploy.portfolioLens();
        positionManager = deploy.positionManager();
        position = SingleAssetPosition(_deployPosition());

        erc201 = new MintableToken();

        positionManager.toggleKnownContract(address(erc201));
    }

    function testPositionSanityCheck() public {
        assertEq(position.TYPE(), 0x2);
        assertEq(position.getAssets().length, 0);
        assertEq(position.getDebtPools().length, 0);
        assertEq(address(positionManager), position.positionManager());
        assertEq(positionManager.ownerOf(address(position)), address(this));
    }

    function testApproveTokens(address spender, uint256 amt) public {
        vm.assume(amt < BIG_NUMBER);

        bytes memory data = abi.encode(spender, address(erc201), amt);
        Action memory action = Action({op: Operation.Approve, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.processBatch(address(position), actions);
        assertEq(erc201.allowance(address(position), spender), amt);
    }

    function testSingleAssetSingleDeposit(uint256 amt) public {
        vm.assume(amt < BIG_NUMBER);
        erc201.mint(address(this), amt);
        erc201.approve(address(positionManager), type(uint256).max);

        bytes memory data = abi.encode(address(this), erc201, amt);
        Action memory action = Action({op: Operation.Deposit, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.processBatch(address(position), actions);
        assertEq(erc201.balanceOf(address(this)), 0);
        assertEq(erc201.balanceOf(address(position)), amt);
    }

    function testSingleAssetMultipleDeposit(uint256 amt) public {
        vm.assume(amt < BIG_NUMBER);

        erc201.mint(address(this), amt);
        erc201.approve(address(positionManager), type(uint256).max);

        bytes memory data = abi.encode(address(this), address(erc201), amt / 2);
        Action memory action = Action({op: Operation.Deposit, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.processBatch(address(position), actions);
        assertEq(erc201.balanceOf(address(position)), amt / 2);

        data = abi.encode(address(this), address(erc201), amt - (amt / 2));
        action = Action({op: Operation.Deposit, data: data});
        actions[0] = action;

        positionManager.processBatch(address(position), actions);
        assertEq(erc201.balanceOf(address(position)), amt);
    }

    function testSingleAssetSingleWithdraw(uint256 amt) public {
        vm.assume(amt < BIG_NUMBER);
        erc201.mint(address(position), amt);

        bytes memory data = abi.encode(address(this), erc201, amt);
        Action memory action = Action({op: Operation.Transfer, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.processBatch(address(position), actions);
        assertEq(erc201.balanceOf(address(this)), amt);
        assertEq(erc201.balanceOf(address(position)), 0);
    }

    function testSingleAssetMultipleWithdraw(uint256 amt) public {
        vm.assume(amt < BIG_NUMBER);

        erc201.mint(address(position), amt);

        bytes memory data = abi.encode(address(this), address(erc201), amt / 2);
        Action memory action = Action({op: Operation.Transfer, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.processBatch(address(position), actions);
        assertEq(erc201.balanceOf(address(this)), amt / 2);

        data = abi.encode(address(this), address(erc201), amt - (amt / 2));
        action = Action({op: Operation.Transfer, data: data});
        actions[0] = action;

        positionManager.processBatch(address(position), actions);
        assertEq(erc201.balanceOf(address(this)), amt);
    }

    function _deployPosition() internal returns (address) {
        uint256 POSITION_TYPE = 0x2;
        bytes32 salt = "SingleAssetPosition";
        bytes memory data = abi.encode(address(this), POSITION_TYPE, salt);
        address positionAddress = portfolioLens.predictAddress(POSITION_TYPE, salt);

        Action memory action = Action({op: Operation.NewPosition, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.processBatch(positionAddress, actions);

        return positionAddress;
    }
}
