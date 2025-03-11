// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { AggV3Oracle } from "src/oracle/AggV3Oracle.sol";

contract DeployAggV3Oracle is BaseScript {
    AggV3Oracle oracle;

    address asset;
    address assetFeed;
    uint256 assetDecimals;
    uint256 assetFeedDecimals;
    bool assetFeedCheckTimestamp;
    uint256 assetStalePriceThreshold;
    bool isUsdFeed;
    address eth;
    address ethFeed;
    uint256 ethFeedDecimals;
    bool ethFeedCheckTimestamp;
    uint256 ethStalePriceThreshold;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new AggV3Oracle(
            asset,
            assetFeed,
            assetDecimals,
            assetFeedDecimals,
            assetFeedCheckTimestamp,
            assetStalePriceThreshold,
            isUsdFeed,
            eth,
            ethFeed,
            ethFeedDecimals,
            ethFeedCheckTimestamp,
            ethStalePriceThreshold
        );
        console2.log("AggV3Oracle: ", address(oracle));
    }

    function getParams() internal {
        asset = vm.parseJsonAddress(getConfig(), "$.DeployAggV3Oracle.asset");
        assetFeed = vm.parseJsonAddress(getConfig(), "$.DeployAggV3Oracle.assetFeed");
        assetDecimals = vm.parseJsonUint(getConfig(), "$.DeployAggV3Oracle.assetDecimals");
        assetFeedDecimals = vm.parseJsonUint(getConfig(), "$.DeployAggV3Oracle.assetFeedDecimals");
        assetFeedCheckTimestamp = vm.parseJsonBool(getConfig(), "$.DeployAggV3Oracle.assetFeedCheckTimestamp");
        assetStalePriceThreshold = vm.parseJsonUint(getConfig(), "$.DeployAggV3Oracle.assetStalePriceThreshold");
        isUsdFeed = vm.parseJsonBool(getConfig(), "$.DeployAggV3Oracle.isUsdFeed");
        eth = vm.parseJsonAddress(getConfig(), "$.DeployAggV3Oracle.eth");
        ethFeed = vm.parseJsonAddress(getConfig(), "$.DeployAggV3Oracle.ethFeed");
        ethFeedDecimals = vm.parseJsonUint(getConfig(), "$.DeployAggV3Oracle.ethFeedDecimals");
        ethFeedCheckTimestamp = vm.parseJsonBool(getConfig(), "$.DeployAggV3Oracle.ethFeedCheckTimestamp");
        ethStalePriceThreshold = vm.parseJsonUint(getConfig(), "$.DeployAggV3Oracle.ethStalePriceThreshold");
    }
}
