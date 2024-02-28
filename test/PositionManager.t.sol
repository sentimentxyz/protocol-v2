// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest, MintableToken} from "./BaseTest.sol";
import {PoolDeployParams} from "src/PoolFactory.sol";
import {Operation, Action, PositionDeployed, PositionManager} from "src/PositionManager.sol";
import {Vm} from "forge-std/Test.sol";
import {IPosition} from "src/interface/IPosition.sol";
import {PortfolioLens} from "src/lens/PortfolioLens.sol";
import {Errors} from "src/lib/Errors.sol";

contract PositionManagerTest is BaseTest {
    MintableToken mockToken;

    function setUp() public override {
        super.setUp();
        mockToken = new MintableToken();
    }

    function testOwnerFunctions() public {
        // todo!()
    }

    function testReentrantFunctions() public {
        // todo!()
    }

    function processRevertsForUnknownOperation() public {
        // todo!
        // will need to create maliciouls call data
    }

    function testChangePositionImpl() public {
        // todo!
    }

    function testCantCallNonAuthorizedFunctions() public {
        address nonAuthedTarget = address(69);

        uint256 typee = 1;
        bytes32 salt = keccak256("testCantCallNonAuthorizedFunctions");

        address position = _deployPosition(typee, salt, address(this));
        bytes memory callData = hex"1234567890abcdef";
        bytes memory data = abi.encodePacked(nonAuthedTarget, callData);

        Action memory action = Action({op: Operation.Exec, data: data});

        Action[] memory actions = new Action[](1);
        actions[0] = action;

        // we shouldnt be able to call this function yet
        PositionManager _manager = PositionManager(deploy.positionManager());
        vm.expectRevert();
        _manager.processBatch(position, actions);

        // toggling it should allow us to call them
        _manager.toggleKnownFunc(nonAuthedTarget, bytes4(callData));
        _manager.processBatch(position, actions);
    }

    function testCantApproveNonAuthorizedAddress() public {
        uint256 typee = 1;
        bytes32 salt = keccak256("testCantCallNonAuthorizedFunctions");
        address nonAuthedTarget = address(this);

        address position = _deployPosition(typee, salt, address(this));

        Action memory action =
            Action({op: Operation.Approve, data: abi.encode(nonAuthedTarget, address(mockToken), uint256(100))});

        Action[] memory actions = new Action[](1);
        actions[0] = action;

        // we shouldnt be able to call this function yet
        PositionManager _manager = PositionManager(deploy.positionManager());
        vm.expectRevert();
        _manager.processBatch(position, actions);

        // toggling it should allow us to call them
        _manager.toggleKnownContract(address(mockToken));
        _manager.processBatch(position, actions);
    }

    function testAuthPositionAllowsCaller() public {
        uint256 typee = 1;
        bytes32 salt = keccak256("testAuthPositionAllowsCaller");
        address owner = address(10);

        address position = _deployPosition(typee, salt, owner);

        mockToken.mint(address(this), 100);
        mockToken.approve(address(deploy.positionManager()), 100);

        PositionManager _manager = PositionManager(deploy.positionManager());

        vm.expectRevert();
        _manager.processBatch(position, depositActionFromThis(address(mockToken), 100));

        vm.prank(owner);
        _manager.toggleAuth(address(this), position);

        _manager.processBatch(position, depositActionFromThis(address(mockToken), 100));
    }

    function testNonAuthCantCallPositionProcess() public {
        uint256 typee = 1;
        bytes32 salt = keccak256("testNonAuthCantCallPositionProcess");
        address owner = address(10);

        address position = _deployPosition(typee, salt, owner);

        mockToken.mint(address(this), 100);
        mockToken.approve(address(deploy.positionManager()), 100);

        PositionManager _manager = PositionManager(deploy.positionManager());

        vm.expectRevert(Errors.UnauthorizedAction.selector);
        _manager.processBatch(position, depositActionFromThis(address(mockToken), 100));
    }

    function testCanCreatePositionType1() public {
        bytes32 salt = keccak256("test");
        uint256 typee = 1;

        _testDeployPosition(typee, salt);
    }

    function testCanCreatePositionType2() public {
        bytes32 salt = keccak256("test");
        uint256 typee = 2;

        _testDeployPosition(typee, salt);
    }

    function _testDeployPosition(uint256 typee, bytes32 salt) internal {
        vm.recordLogs();
        address predicted = _deployPosition(typee, salt, address(this));

        // check that the position was deployed as expcected
        address position = getNewPositionsDeployedFromRecordedLogs();
        assertEq(position, predicted);

        // check were the owner and authed
        assertEq(PositionManager(deploy.positionManager()).ownerOf(position), address(this));
        assertEq(PositionManager(deploy.positionManager()).isAuth(position, address(this)), true);
        assertEq(IPosition(position).TYPE(), typee);
    }

    function testFailDeployType1TwiceWithSameSalt() public {
        bytes32 salt = keccak256("test");
        uint256 typee = 1;

        _testDeployPosition(typee, salt);
        _testDeployPosition(typee, salt);
    }

    function testFailDeployType2TwiceWithSameSalt() public {
        bytes32 salt = keccak256("test");
        uint256 typee = 2;

        _testDeployPosition(typee, salt);
        _testDeployPosition(typee, salt);
    }

    function _deployPool(address token) internal {}

    function _deployPosition(uint256 typee, bytes32 salt, address owner) internal returns (address) {
        address predicted = predictAddress(typee, salt);

        Action memory action = Action({op: Operation.NewPosition, data: abi.encode(owner, typee, salt)});

        Action[] memory actions = new Action[](1);
        actions[0] = action;

        PositionManager(deploy.positionManager()).processBatch(predicted, actions);

        return predicted;
    }

    function predictAddress(uint256 typee, bytes32 salt) internal view returns (address) {
        return PortfolioLens(deploy.portfolioLens()).predictAddress(typee, salt);
    }

    function depositActionFromThis(address token, uint256 amt) internal view returns (Action[] memory) {
        Action memory action = Action({op: Operation.Deposit, data: abi.encode(address(this), token, amt)});

        Action[] memory actions = new Action[](1);
        actions[0] = action;
        return actions;
    }

    function getNewPositionsDeployedFromRecordedLogs() internal returns (address) {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == PositionDeployed.selector) {
                return address(uint160(uint256(logs[i].topics[1])));
            }
        }

        return address(0);
    }
}

contract AllowedContractMock {
    function callMe() public pure returns (bool) {
        return true;
    }
}
