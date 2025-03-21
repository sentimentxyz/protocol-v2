// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IOracle } from "src/interfaces/IOracle.sol";

interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

// @notice Latest price update for `asset` was older than the accepted threshold
error AggV3Oracle_StalePrice(address asset);

// @title AggV3Oracle
// @notice General purpose AggregatorV3-compliant price oracle
contract AggV3Oracle is IOracle {
    using Math for uint256;

    address public immutable ASSET;
    address public immutable ASSET_FEED;
    uint256 public immutable ASSET_DECIMALS; // Decimals for ASSET
    uint256 public immutable ASSET_FEED_DECIMALS; // Decimals for ASSET_FEED
    bool public immutable ASSET_FEED_CHECK_TIMESTAMP; // True if ASSET_FEED prices must be checked for staleness
    uint256 public immutable ASSET_STALE_PRICE_THRESHOLD; // In seconds

    bool public immutable IS_USD_FEED; // True if ASSET_FEED is USD-denominated

    // If IS_USD_FEED is false, the following variables will not be set or used
    address public immutable ETH;
    address public immutable ETH_FEED;
    uint256 public immutable ETH_FEED_DECIMALS; // Decimals for ETH_FEED
    bool public immutable ETH_FEED_CHECK_TIMESTAMP; // True if ETH_FEED prices must be checked for staleness
    uint256 public immutable ETH_STALE_PRICE_THRESHOLD; // In seconds

    constructor(
        address asset,
        address assetFeed,
        uint256 assetDecimals,
        uint256 assetFeedDecimals,
        bool assetFeedCheckTimestamp,
        uint256 assetStalePriceThreshold,
        bool isUsdFeed,
        address eth,
        address ethFeed,
        uint256 ethFeedDecimals,
        bool ethFeedCheckTimestamp,
        uint256 ethStalePriceThreshold
    ) {
        ASSET = asset;
        ASSET_FEED = assetFeed;
        ASSET_DECIMALS = assetDecimals;
        ASSET_FEED_DECIMALS = assetFeedDecimals;
        ASSET_FEED_CHECK_TIMESTAMP = assetFeedCheckTimestamp;
        ASSET_STALE_PRICE_THRESHOLD = assetStalePriceThreshold;

        IS_USD_FEED = isUsdFeed; // If false, the feed is assumed to be ETH-denominated

        if (isUsdFeed) {
            ETH = eth;
            ETH_FEED = ethFeed;
            ETH_FEED_DECIMALS = ethFeedDecimals;
            ETH_FEED_CHECK_TIMESTAMP = ethFeedCheckTimestamp;
            ETH_STALE_PRICE_THRESHOLD = ethStalePriceThreshold;
        }
    }

    function getValueInEth(address, uint256 amt) external view returns (uint256 value) {
        uint256 assetPrice =
            _getPrice(ASSET_FEED, ASSET_FEED_CHECK_TIMESTAMP, ASSET_STALE_PRICE_THRESHOLD, ASSET_FEED_DECIMALS, ASSET);

        uint256 ethPrice = 1e18; // Default value when ASSET_FEED is ETH-denominated
        if (IS_USD_FEED) {
            ethPrice = _getPrice(ETH_FEED, ETH_FEED_CHECK_TIMESTAMP, ETH_STALE_PRICE_THRESHOLD, ETH_FEED_DECIMALS, ETH);
        }

        // Scale amt to 18 decimals
        uint256 scaledAmt = amt;
        if (ASSET_DECIMALS < 18) scaledAmt = amt * (10 ** (18 - ASSET_DECIMALS));
        if (ASSET_DECIMALS > 18) scaledAmt = amt / (10 ** (ASSET_DECIMALS - 18));

        return scaledAmt.mulDiv(assetPrice, ethPrice);
    }

    function _getPrice(
        address feed,
        bool checkTimestamp,
        uint256 stalePriceThreshold,
        uint256 feedDecimals,
        address asset
    )
        internal
        view
        returns (uint256 scaledPrice)
    {
        (, int256 answer,, uint256 updatedAt,) = IAggregatorV3(feed).latestRoundData();

        if (checkTimestamp) if (updatedAt < block.timestamp - stalePriceThreshold) revert AggV3Oracle_StalePrice(asset);

        scaledPrice = uint256(answer);
        if (feedDecimals < 18) scaledPrice = scaledPrice * (10 ** (18 - feedDecimals));
        if (feedDecimals > 18) scaledPrice = scaledPrice / (10 ** (feedDecimals - 18));
    }
}
