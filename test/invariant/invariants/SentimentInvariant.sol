// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.24;

import { OracleHandler } from "../handlers/OracleHandler.sol";
import { PoolHandler } from "../handlers/PoolHandler.sol";
import { PositionManagerHandler } from "../handlers/PositionManagerHandler.sol";
import { SuperPoolHandler } from "../handlers/SuperPoolHandler.sol";

// forgefmt: disable-start
/**************************************************************************************************************/
/*** SentimentInvariant is the highest level contract that contains all setup, handlers, and invariants for ***/
/*** the Sentiment Fuzz Suite.                                                                              ***/
/**************************************************************************************************************/
// forgefmt: disable-end

contract SentimentInvariant is PoolHandler, PositionManagerHandler, SuperPoolHandler, OracleHandler {
    constructor() payable {
        setup();
    }
}
