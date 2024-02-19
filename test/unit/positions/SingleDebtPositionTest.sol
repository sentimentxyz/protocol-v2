// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest, MintableToken} from "../BaseTest.sol";
import {PortfolioLens} from "src/lens/PortfolioLens.sol";
import {SingleDebtPosition} from "src/positions/SingleDebtPosition.sol";
import {PositionManager, Operation, Action} from "src/PositionManager.sol";

import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract SingleDebtPositionTest is BaseTest {
    SingleDebtPosition position;
    PortfolioLens portfolioLens;
    PositionManager positionManager;

    function setUp() public override {
        super.setUp();
        portfolioLens = deploy.portfolioLens();
        positionManager = deploy.positionManager();
        position = SingleDebtPosition(_deploySingleDebtPosition());
    }

    function testPositionSanityCheck() public {
        assertEq(position.TYPE(), 0x1);
        assertEq(position.getAssets(), new address[](0));
        assertEq(position.getDebtPools()[0], address(0));
        assertEq(address(positionManager), position.positionManager());
        assertEq(positionManager.ownerOf(address(position)), address(this));
    }

    function testApproveTokens(address spender, uint256 amt) public {
        vm.assume(amt < BIG_NUMBER);
        MockERC20 erc20 = new MockERC20();
        positionManager.toggleKnownContract(address(erc20));

        bytes memory data = abi.encode(address(erc20), amt);
        Action memory action = Action({op: Operation.Approve, target: spender, data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.process(address(position), actions);
        assertEq(erc20.allowance(address(position), spender), amt);
    }

    function testSingleAssetSingleDeposit(uint256 amt) public {
        vm.assume(amt < BIG_NUMBER);
        MintableToken erc20 = new MintableToken();
        erc20.mint(address(this), amt);
        positionManager.toggleKnownContract(address(erc20));
        erc20.approve(address(positionManager), type(uint256).max);

        bytes memory data = abi.encode(erc20, amt);
        Action memory action = Action({op: Operation.Deposit, target: address(this), data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.process(address(position), actions);
        assertEq(erc20.balanceOf(address(position)), amt);
    }

    function testSingleAssetMultipleDeposit(uint256 amt) public {
        vm.assume(amt < BIG_NUMBER / 2);

        MintableToken erc20 = new MintableToken();
        erc20.mint(address(this), amt * 2);
        erc20.approve(address(positionManager), type(uint256).max);

        positionManager.toggleKnownContract(address(erc20));

        bytes memory data = abi.encode(address(erc20), amt);
        Action memory action = Action({op: Operation.Deposit, target: address(this), data: data});
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        positionManager.process(address(position), actions);
        assertEq(erc20.balanceOf(address(position)), amt);

        positionManager.process(address(position), actions);
        assertEq(erc20.balanceOf(address(position)), amt * 2);
    }

    function testMultipleAssetSingleDeposit(uint256 amt1, uint256 amt2) public {
        vm.assume(amt1 < BIG_NUMBER);
        vm.assume(amt2 < BIG_NUMBER);

        MintableToken erc201 = new MintableToken();
        erc201.mint(address(this), amt1);
        positionManager.toggleKnownContract(address(erc201));
        erc201.approve(address(positionManager), type(uint256).max);

        MintableToken erc202 = new MintableToken();
        erc202.mint(address(this), amt2);
        positionManager.toggleKnownContract(address(erc202));
        erc202.approve(address(positionManager), type(uint256).max);

        bytes memory data1 = abi.encode(erc201, amt1);
        Action memory action1 = Action({op: Operation.Deposit, target: address(this), data: data1});

        bytes memory data2 = abi.encode(erc202, amt2);
        Action memory action2 = Action({op: Operation.Deposit, target: address(this), data: data2});

        Action[] memory actions = new Action[](2);
        actions[0] = action1;
        actions[1] = action2;

        positionManager.process(address(position), actions);

        assertEq(erc201.balanceOf(address(position)), amt1);
        assertEq(erc202.balanceOf(address(position)), amt2);
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
}
