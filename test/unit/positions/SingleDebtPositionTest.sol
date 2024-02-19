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

    function testDeposit(uint256 amt) public {
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
