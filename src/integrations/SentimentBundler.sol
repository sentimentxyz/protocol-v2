// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

import {WNativeBundler} from "./WNativeBundler.sol";
import {TransferBundler} from "./TransferBundler.sol";
import {ISentiment, Action} from "./interfaces/ISentiment.sol";
import {SafeTransferLib, ERC20} from "./libraries/SafeTransferLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";

/// @title SentimentBundler
/// @author Based on Morpho Labs' bundler pattern
/// @notice Simplified bundler contract for interacting with Sentiment protocol positions
/// @dev Inherits from WNativeBundler and TransferBundler to provide ETH wrapping and transfer functionality
contract SentimentBundler is WNativeBundler, TransferBundler {
    using SafeTransferLib for ERC20;

    /* IMMUTABLES */

    /// @notice The Sentiment PositionManager contract
    ISentiment public immutable POSITION_MANAGER;

    /* CONSTRUCTOR */

    constructor(
        address positionManager,
        address wNative
    ) WNativeBundler(wNative) {
        require(positionManager != address(0), ErrorsLib.ZERO_ADDRESS);
        POSITION_MANAGER = ISentiment(positionManager);
    }

    /* ACTIONS */

    /// @notice Process a batch of actions on a position
    /// @param position Position address
    /// @param actions List of actions to process
    function processBatch(
        address position,
        Action[] calldata actions
    ) external payable protected {
        require(position != address(0), ErrorsLib.ZERO_ADDRESS);
        require(actions.length > 0, ErrorsLib.EMPTY_ARRAY);

        // Use delegatecall to preserve msg.sender
        bytes memory data = abi.encodeWithSelector(
            POSITION_MANAGER.processBatch.selector,
            position,
            actions
        );
        (bool success, bytes memory returnData) = address(POSITION_MANAGER)
            .delegatecall(data);
        if (!success) _revert(returnData);
    }
}
