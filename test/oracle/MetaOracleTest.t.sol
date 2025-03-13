// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { console2 } from "forge-std/console2.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IOracle } from "src/interfaces/IOracle.sol";
import { MetaPriceOracle } from "src/oracle/MetaPriceOracle.sol";
import { AggV3Oracle } from "src/oracle/AggV3Oracle.sol";
import { BaseTest } from "test/BaseTest.t.sol";
import { MockV3Aggregator } from "test/mocks/MockV3Aggregator.sol";

contract MetaOracleTest is BaseTest {
    using Math for uint256;

    MockV3Aggregator mockEthFeed;
    MockV3Aggregator mockUsdFeed;
    MockV3Aggregator mockEthPriceFeed;
    AggV3Oracle aggV3OracleA;
    AggV3Oracle aggV3OracleB;
    MetaPriceOracle metaPriceOracle;

    address private constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 public STALE_PRICE_THRESHOLD = 60 minutes;

    function setUp() public pure override {
        super.setUp;
    }

    function testMetaOracle() public {
        aggV3OracleA = AggV3Oracle(0x712047cC3e4b0023Fccc09Ae412648CF23C65ed3); // wHype
        aggV3OracleB = AggV3Oracle(0xb4AEd75ec810729Ee0fD375Ff3ADe8eD03d1eA96); // wstHype/wHype RR


        metaPriceOracle = new MetaPriceOracle(aggV3OracleA, aggV3OracleB, IOracle(address(0)));
        console2.log("aggV3OracleA price: ", aggV3OracleA.getValueInEth(address(0), 1e18));
        console2.log("aggV3OracleB price: ", aggV3OracleB.getValueInEth(address(0), 1e18));
        console2.log("metaPriceOracle price: ", metaPriceOracle.getValueInEth(address(0), 1e18));
    }
}
