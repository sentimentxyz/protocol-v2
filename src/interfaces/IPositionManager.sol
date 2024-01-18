// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IPositionManager {
    enum Operation {
        Exec,
        Repay,
        Borrow,
        Deposit,
        Transfer,
        AddAsset,
        RemoveAsset,
        NewPosition
    }

    struct Action {
        Operation op;
        address target;
        bytes data;
    }

    function setBeacon(uint256 positionType, address beacon) external;
    function process(address position, Action[] calldata actions) external;
    function setAuth(address user, address position, bool isAuthorized) external;
}
