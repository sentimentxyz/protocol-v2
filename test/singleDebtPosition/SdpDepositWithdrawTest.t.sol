// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest, MintableToken} from "../BaseTest.t.sol";
import {PortfolioLens} from "src/lens/PortfolioLens.sol";
import {SingleDebtPosition} from "src/position/SingleDebtPosition.sol";
import {PositionManager, Operation, Action} from "src/PositionManager.sol";

contract SdpDepositWithdrawTest is BaseTest {
    SingleDebtPosition position;
    PortfolioLens portfolioLens;
    PositionManager positionManager;

    MintableToken erc201;
    MintableToken erc202;

    function setUp() public override {
        super.setUp();
        portfolioLens = PortfolioLens(protocol.portfolioLens());
        positionManager = PositionManager(protocol.positionManager());
        position = SingleDebtPosition(_deploySingleDebtPosition());

        erc201 = new MintableToken();
        erc202 = new MintableToken();

        positionManager.toggleKnownContract(address(erc201));
        positionManager.toggleKnownContract(address(erc202));
    }

    function testPositionSanityCheck() public {
        assertEq(position.TYPE(), 0x1);
        assertEq(position.getAssets().length, 0);
        assertEq(address(positionManager), position.positionManager());
        assertEq(positionManager.ownerOf(address(position)), address(this));
    }

    function testApproveTokens(address spender, uint256 amt) public {
        vm.assume(amt < MAX_NUM);

        bytes memory data = abi.encode(spender, address(erc201), amt);
        Action memory action = Action({op: Operation.Approve, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.processBatch(address(position), actions);
        assertEq(erc201.allowance(address(position), spender), amt);
    }

    function testSingleAssetSingleDeposit(uint256 amt) public {
        vm.assume(amt < MAX_NUM);
        erc201.mint(address(this), amt);
        erc201.approve(address(positionManager), type(uint256).max);

        bytes memory data = abi.encode(erc201, amt);
        Action memory action = Action({op: Operation.Deposit, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.processBatch(address(position), actions);
        assertEq(erc201.balanceOf(address(this)), 0);
        assertEq(erc201.balanceOf(address(position)), amt);
    }

    function testSingleAssetMultipleDeposit(uint256 amt) public {
        vm.assume(amt < MAX_NUM);

        erc201.mint(address(this), amt);
        erc201.approve(address(positionManager), type(uint256).max);

        bytes memory data = abi.encode(address(erc201), amt / 2);
        Action memory action = Action({op: Operation.Deposit, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.processBatch(address(position), actions);
        assertEq(erc201.balanceOf(address(position)), amt / 2);

        data = abi.encode(address(erc201), amt - (amt / 2));
        action = Action({op: Operation.Deposit, data: data});
        actions[0] = action;

        positionManager.processBatch(address(position), actions);
        assertEq(erc201.balanceOf(address(position)), amt);
    }

    function testMultipleAssetSingleDeposit(uint256 amt1, uint256 amt2) public {
        vm.assume(amt1 < MAX_NUM);
        vm.assume(amt2 < MAX_NUM);

        erc201.mint(address(this), amt1);
        erc201.approve(address(positionManager), type(uint256).max);

        erc202.mint(address(this), amt2);
        erc202.approve(address(positionManager), type(uint256).max);

        bytes memory data1 = abi.encode(erc201, amt1);
        Action memory action1 = Action({op: Operation.Deposit, data: data1});

        bytes memory data2 = abi.encode(erc202, amt2);
        Action memory action2 = Action({op: Operation.Deposit, data: data2});

        Action[] memory actions = new Action[](2);
        actions[0] = action1;
        actions[1] = action2;

        positionManager.processBatch(address(position), actions);

        assertEq(erc201.balanceOf(address(position)), amt1);
        assertEq(erc202.balanceOf(address(position)), amt2);
    }

    function testMultipleAssetMultipleDeposit(uint256 amt1, uint256 amt2) public {
        vm.assume(amt1 < MAX_NUM);
        vm.assume(amt2 < MAX_NUM);

        erc201.mint(address(this), amt1);
        erc201.approve(address(positionManager), type(uint256).max);

        erc202.mint(address(this), amt2);
        erc202.approve(address(positionManager), type(uint256).max);

        bytes memory data1 = abi.encode(erc201, amt1 / 2);
        Action memory action1 = Action({op: Operation.Deposit, data: data1});

        bytes memory data2 = abi.encode(erc202, amt2 / 2);
        Action memory action2 = Action({op: Operation.Deposit, data: data2});

        Action[] memory actions = new Action[](2);
        actions[0] = action1;
        actions[1] = action2;

        positionManager.processBatch(address(position), actions);

        assertEq(erc201.balanceOf(address(position)), amt1 / 2);
        assertEq(erc202.balanceOf(address(position)), amt2 / 2);

        data1 = abi.encode(erc201, amt1 - (amt1 / 2));
        action1 = Action({op: Operation.Deposit, data: data1});

        data2 = abi.encode(erc202, amt2 - (amt2 / 2));
        action2 = Action({op: Operation.Deposit, data: data2});

        // swap order of actions, shouldn't matter
        actions[0] = action2;
        actions[1] = action1;

        positionManager.processBatch(address(position), actions);
        assertEq(erc201.balanceOf(address(position)), amt1);
        assertEq(erc202.balanceOf(address(position)), amt2);
    }

    function testSingleAssetSingleWithdraw(uint256 amt) public {
        vm.assume(amt < MAX_NUM);
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
        vm.assume(amt < MAX_NUM);

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

    function testMultipleAssetSingleWithdraw(uint256 amt1, uint256 amt2) public {
        vm.assume(amt1 < MAX_NUM);
        vm.assume(amt2 < MAX_NUM);

        erc201.mint(address(position), amt1);
        erc202.mint(address(position), amt2);

        bytes memory data1 = abi.encode(address(this), erc201, amt1);
        Action memory action1 = Action({op: Operation.Transfer, data: data1});

        bytes memory data2 = abi.encode(address(this), erc202, amt2);
        Action memory action2 = Action({op: Operation.Transfer, data: data2});

        Action[] memory actions = new Action[](2);
        actions[0] = action1;
        actions[1] = action2;

        positionManager.processBatch(address(position), actions);

        assertEq(erc201.balanceOf(address(this)), amt1);
        assertEq(erc202.balanceOf(address(this)), amt2);
    }

    function testMultipleAssetMultipleWithdraw(uint256 amt1, uint256 amt2) public {
        vm.assume(amt1 < MAX_NUM);
        vm.assume(amt2 < MAX_NUM);

        erc201.mint(address(position), amt1);
        erc202.mint(address(position), amt2);

        bytes memory data1 = abi.encode(address(this), erc201, amt1 / 2);
        Action memory action1 = Action({op: Operation.Transfer, data: data1});

        bytes memory data2 = abi.encode(address(this), erc202, amt2 / 2);
        Action memory action2 = Action({op: Operation.Transfer, data: data2});

        Action[] memory actions = new Action[](2);
        actions[0] = action1;
        actions[1] = action2;

        positionManager.processBatch(address(position), actions);

        assertEq(erc201.balanceOf(address(this)), amt1 / 2);
        assertEq(erc202.balanceOf(address(this)), amt2 / 2);

        data1 = abi.encode(address(this), address(erc201), amt1 - (amt1 / 2));
        action1 = Action({op: Operation.Transfer, data: data1});

        data2 = abi.encode(address(this), address(erc202), amt2 - (amt2 / 2));
        action2 = Action({op: Operation.Transfer, data: data2});

        // swap order of actions, shouldn't matter
        actions[0] = action2;
        actions[1] = action1;

        positionManager.processBatch(address(position), actions);

        assertEq(erc201.balanceOf(address(this)), amt1);
        assertEq(erc202.balanceOf(address(this)), amt2);
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
}
