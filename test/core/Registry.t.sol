// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTest } from "../BaseTest.t.sol";

contract RegistryTest is BaseTest {
    function testInitializesRegistryCorrectly() public view {
        assertEq(address(pool), registry.addressFor(SENTIMENT_POOL_KEY));
        assertEq(address(riskEngine), registry.addressFor(SENTIMENT_RISK_ENGINE_KEY));
        assertEq(address(positionManager), registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));
        assertEq(address(positionBeacon), registry.addressFor(SENTIMENT_POSITION_BEACON_KEY));
        assertEq(address(riskModule), registry.addressFor(SENTIMENT_RISK_MODULE_KEY));

        assertEq(pool.positionManager(), address(positionManager));

        assertEq(address(positionManager.riskEngine()), address(riskEngine));
        assertEq(address(positionManager.pool()), address(pool));
        assertEq(address(positionManager.positionBeacon()), address(positionBeacon));
    }
}
