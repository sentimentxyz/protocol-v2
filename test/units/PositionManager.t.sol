// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseTest.t.sol";
import {FixedRateModel} from "../../src/irm/FixedRateModel.sol";
import {LinearRateModel} from "../../src/irm/LinearRateModel.sol";

import { Action, Operation } from "src/PositionManager.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

contract PositionManagerUnitTests is BaseTest {
    address public owner = address(0x5);

    function testInitializePosition() public {
        bytes32 salt = bytes32(uint256(43534853));
        bytes memory data = abi.encode(owner, salt);
        owner = address(0x05);

        (address expectedAddress, ) = portfolioLens.predictAddress(owner, salt);

        Action memory action = Action({op: Operation.NewPosition, data: data});

        Action[] memory actions = new Action[](1);
        actions[0] = action;

        PositionManager(positionManager).processBatch(expectedAddress, actions);

        uint32 size;
        assembly {
            size := extcodesize(expectedAddress)
        }

        assertGt(size, 0);
    }
}