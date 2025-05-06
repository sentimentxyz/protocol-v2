// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

/// @title ErrorsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library exposing error messages.
library ErrorsLib {
    /* STANDARD BUNDLERS */

    /// @dev Thrown when a call is attempted while the bundler is not in an initiated execution context.
    string internal constant UNINITIATED = "uninitiated";

    /// @dev Thrown when a multicall is attempted while the bundler in an initiated execution context.
    string internal constant ALREADY_INITIATED = "already initiated";

    /// @dev Thrown when a call is attempted from an unauthorized sender.
    string internal constant UNAUTHORIZED_SENDER = "unauthorized sender";

    /// @dev Thrown when a call is attempted with a zero address as input.
    string internal constant ZERO_ADDRESS = "zero address";

    /// @dev Thrown when a call is attempted with the bundler address as input.
    string internal constant BUNDLER_ADDRESS = "bundler address";

    /// @dev Thrown when a call is attempted with a zero amount as input.
    string internal constant ZERO_AMOUNT = "zero amount";

    /// @dev Thrown when a call is attempted with a zero shares as input.
    string internal constant ZERO_SHARES = "zero shares";

    /// @dev Thrown when a call reverts with empty `returnData`.
    string internal constant CALL_FAILED = "call failed";

    /// @dev Thrown when the given owner is unexpected.
    string internal constant UNEXPECTED_OWNER = "unexpected owner";

    /// @dev Thrown when an action ends up minting/burning more shares than a given slippage.
    string internal constant SLIPPAGE_EXCEEDED = "slippage exceeded";

    /// @dev Thrown when a call to depositFor fails.
    string internal constant DEPOSIT_FAILED = "deposit failed";

    /// @dev Thrown when a call to withdrawTo fails.
    string internal constant WITHDRAW_FAILED = "withdraw failed";

    /// @dev Thrown when an array is empty when it shouldn't be.
    string internal constant EMPTY_ARRAY = "empty array";

    /// @dev Thrown when array lengths don't match when they should.
    string internal constant LENGTH_MISMATCH = "length mismatch";
}
