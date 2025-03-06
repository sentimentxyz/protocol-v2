// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { console2 } from "forge-std/console2.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { AggV3Oracle } from "src/oracle/AggV3Oracle.sol";
import { BaseTest } from "test/BaseTest.t.sol";
import { MockV3Aggregator } from "test/mocks/MockV3Aggregator.sol";

contract AggV3OracleTest is BaseTest {
    using Math for uint256;

    MockV3Aggregator mockEthFeed;
    MockV3Aggregator mockUsdFeed;
    MockV3Aggregator mockEthPriceFeed;
    AggV3Oracle aggV3Oracle;

    address private constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 public STALE_PRICE_THRESHOLD = 60 minutes;

    function setUp() public override {
        super.setUp;

        vm.warp(block.timestamp + 1 days);
        mockEthFeed = new MockV3Aggregator(18, 2e18);
        mockUsdFeed = new MockV3Aggregator(6, 1e6);
        mockEthPriceFeed = new MockV3Aggregator(8, 2220e8);
    }

    function testRevertIfStale() public {
        MockV3Aggregator mockFeed = new MockV3Aggregator(18, 1e18);
        aggV3Oracle = new AggV3Oracle(
            address(asset1),
            address(mockFeed),
            18,
            18,
            true,
            STALE_PRICE_THRESHOLD,
            false,
            address(0),
            address(0),
            0,
            false,
            0
        );
        mockFeed.updateRoundData(1, 1e18, block.timestamp - 61 minutes, block.timestamp - 61 minutes);
        vm.expectRevert();
        aggV3Oracle.getValueInEth(address(0), 1e18);
    }

    function testEthOracle() public {
        aggV3Oracle = new AggV3Oracle(
            address(asset1),
            address(mockEthFeed),
            18,
            18,
            true,
            STALE_PRICE_THRESHOLD,
            false,
            address(0),
            address(0),
            0,
            false,
            0
        );
        assertEq(aggV3Oracle.getValueInEth(address(0), 2e18), 4e18); // price should be 2e18 * 2 asset units = 4e18
    }

    function testUsdOracle() public {
        aggV3Oracle = new AggV3Oracle(
            address(asset2),
            address(mockUsdFeed),
            6,
            6,
            true,
            STALE_PRICE_THRESHOLD,
            true,
            ETH,
            address(mockEthPriceFeed),
            8,
            true,
            STALE_PRICE_THRESHOLD
        );
        assertEq(aggV3Oracle.getValueInEth(address(0), 1e6), uint256(1e18).mulDiv(1e18, 2220e18));
    }
}
