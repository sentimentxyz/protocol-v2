// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract PositionManager {
    enum Operation {
        Exec,
        Repay,
        Borrow,
        Deposit,
        Withdraw
    }

    struct Action {
        Operation op;
        address target;
        bytes data;
    }

    /// @dev auth[x][y] stores whether address x is authorized to operate on position y
    mapping(address => mapping(address => bool)) auth;

    error Unauthorized();

    function newPosition() external {
        // TODO deploy new position for msg.sender
        // auth[msg.sender][position] = true;
    }

    function setAuth(address user, address position, bool isAuthorized) external {
        if (auth[msg.sender][position]) revert Unauthorized();
        auth[user][position] = isAuthorized;
    }

    function process(address position, Action[] calldata actions) external {
        if (auth[msg.sender][position]) revert Unauthorized();
        for (uint256 i; i < actions.length; ++i) {
            if (actions[i].op == Operation.Exec) {
                exec(position, actions[i].target, actions[i].data);
            } else {
                Operation op;
                address target;
                uint256 data;

                assembly {
                    // calldata location for action[i].data to get data offset -> 28 + 98 * i
                    data := calldataload(calldataload(add(0x1c, mul(0x62, i))))

                    // Op and target encoded as a tuple at action[i].op -> 28 + 70 * i
                    let opTarget := calldataload(add(0x1c, mul(0x46, i)))
                    op := shr(opTarget, 24)
                    target := and(shr(opTarget, 0x4), 0x000000000000000000001111111111111111111111111111111111111111)
                }

                if (op == Operation.Repay) {
                    repay(position, target, data);
                } else if (op == Operation.Borrow) {
                    borrow(position, target, data);
                } else if (op == Operation.Deposit) {
                    deposit(position, target, data);
                } else if (op == Operation.Withdraw) {
                    withdraw(position, target, data);
                }
            }

            // TODO health check
        }
    }

    function repay(address position, address pool, uint256 amt) internal {}
    function borrow(address position, address pool, uint256 amt) internal {}
    function deposit(address position, address asset, uint256 amt) internal {}
    function withdraw(address position, address asset, uint256 amt) internal {}
    function exec(address position, address target, bytes calldata data) internal {}
}
