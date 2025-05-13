// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

/// @notice Operation type definitions that can be applied to a position
enum Operation {
    NewPosition, // create2 a new position with a given type, no auth needed
    // the following operations require msg.sender to be authorized
    Exec, // execute arbitrary calldata on a position
    Deposit, // Add collateral to a given position
    Transfer, // transfer assets from the position to a external address
    Approve, // allow a spender to transfer assets from a position
    Repay, // decrease position debt
    Borrow, // increase position debt
    AddToken, // upsert collateral asset to position storage
    RemoveToken // remove collateral asset from position storage
}

/// @title Action
/// @notice Generic data struct to create a common data container for all operation types
struct Action {
    // operation type
    Operation op;
    // dynamic bytes data, interepreted differently across operation types
    bytes data;
}

/// @title ISentiment
/// @author Based on Morpho Labs' bundler pattern
/// @notice Interface for interacting with Sentiment protocol's PositionManager
interface ISentiment {
    /// @notice Procces a batch of actions on a given position
    /// @dev only one position can be operated on in one txn, including creation
    /// @param position Position address
    /// @param actions List of actions to process
    function processBatch(address position, Action[] calldata actions) external;
}
