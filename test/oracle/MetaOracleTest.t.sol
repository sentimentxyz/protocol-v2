// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { console2 } from "forge-std/console2.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IOracle } from "src/interfaces/IOracle.sol";

import { AggV3Oracle } from "src/oracle/AggV3Oracle.sol";
import { MetaOracle } from "src/oracle/MetaOracle.sol";
import { BaseTest } from "test/BaseTest.t.sol";
import { MockV3Aggregator } from "test/mocks/MockV3Aggregator.sol";

contract MetaOracleTest is BaseTest {
    using Math for uint256;

    MockV3Aggregator mockEthFeed;
    MockV3Aggregator mockUsdFeed;
    MockV3Aggregator mockEthPriceFeed;
    AggV3Oracle aggV3OracleA;
    AggV3Oracle aggV3OracleB;
    MetaOracle metaOracle;

    address private constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 public STALE_PRICE_THRESHOLD = 60 minutes;

    function setUp() public pure override {
        super.setUp;
    }

    function testMetaOracle() public {
        aggV3OracleA = AggV3Oracle(0x712047cC3e4b0023Fccc09Ae412648CF23C65ed3); // wHype
        aggV3OracleB = AggV3Oracle(0xb4AEd75ec810729Ee0fD375Ff3ADe8eD03d1eA96); // wstHype/wHype RR, returns 18 decimals
        metaOracle = new MetaOracle(
            address(aggV3OracleA),
            address(aggV3OracleB),
            address(0),
            aggV3OracleA.ASSET(),
            aggV3OracleB.ASSET(),
            address(0),
            18,
            18,
            18,
            18
        );

        console2.log("aggV3OracleA price: ", aggV3OracleA.getValueInEth(address(0), 1e18));
        console2.log("aggV3OracleB price: ", aggV3OracleB.getValueInEth(address(0), 1e18));
        console2.log("metaOracle price: ", metaOracle.getValueInEth(address(0), 1e18));
    }

    function testVariableDecimals() public {
        vm.warp(block.timestamp + 1 days);

        mockEthFeed = new MockV3Aggregator(18, 1e18);
        mockUsdFeed = new MockV3Aggregator(6, 1e6);
        mockEthPriceFeed = new MockV3Aggregator(8, 2000e8);

        aggV3OracleA = new AggV3Oracle(
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

        aggV3OracleB = new AggV3Oracle(
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

        uint256 assetDecimals = 18;
        metaOracle = new MetaOracle(
            address(aggV3OracleA),
            address(aggV3OracleB),
            address(0),
            aggV3OracleA.ASSET(),
            aggV3OracleB.ASSET(),
            address(0),
            assetDecimals,
            18,
            6,
            18
        );

        assertEq(
            metaOracle.getValueInEth(address(0), 1e18),
            aggV3OracleA.getValueInEth(address(0), 1e18) * aggV3OracleB.getValueInEth(address(0), 1e6)
                / (10 ** assetDecimals)
        );
    }
}
