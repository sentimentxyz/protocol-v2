// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest, MintableToken} from "./BaseTest.sol";
import {PoolDeployParams} from "src/PoolFactory.sol";
import {Operation, Action, PositionDeployed, PositionManager} from "src/PositionManager.sol";
import {Vm} from "forge-std/Test.sol";
import {IPosition} from "src/interfaces/IPosition.sol";

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

    function testCantCallNonAuthorizedFunctions(address nonAuthedTarget) public {
        vm.assume(nonAuthedTarget != address(0));

        uint256 typee = 1;
        bytes32 salt = keccak256("testCantCallNonAuthorizedFunctions");

        address position = _deployPosition(typee, salt, address(this));

        Action memory action =
            Action({op: Operation.Exec, target: nonAuthedTarget, data: abi.encodePacked(bytes4(0x12345678))});

        Action[] memory actions = new Action[](1);
        actions[0] = action;

        PositionManager _manager = deploy.positionManager();
        vm.expectRevert();
        _manager.process(position, actions);

        // toggling it should allow us to call them
        _manager.toggleFuncUniverseInclusion(nonAuthedTarget, bytes4(0x12345678));
        _manager.process(position, actions);
    }

    function testCantApproveNonAuthorizedAddress() public {}

    function testChangePositionImpl() public {}

    function testAuthPositionAllowsCaller() public {}

    function testNonAuthCantCallPositionProcess() public {}

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
        assertEq(deploy.positionManager().ownerOf(position), address(this));
        assertEq(deploy.positionManager().auth(address(this), position), true);
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

    function processRevertsForUnknownOperation() public {
        // todo!
        // will need to create maliciouls call data
    }

    function _deployPool(address token) internal {}

    function _deployPosition(uint256 typee, bytes32 salt, address owner) internal returns (address) {
        address predicted = predictAddress(typee, salt);

        Action memory action = Action({op: Operation.NewPosition, target: owner, data: abi.encode(typee, salt)});

        Action[] memory actions = new Action[](1);
        actions[0] = action;

        deploy.positionManager().process(predicted, actions);

        return predicted;
    }

    function predictAddress(uint256 typee, bytes32 salt) internal returns (address) {
        return deploy.positionManager().predictAddress(typee, salt);
    }

    function getNewPositionsDeployedFromRecordedLogs() internal returns (address) {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == PositionDeployed.selector) {
                return address(uint160(uint256(logs[i].topics[1])));
            }
        }
    }
}
