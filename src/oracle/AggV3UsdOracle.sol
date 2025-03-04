// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IOracle } from "../interfaces/IOracle.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

error AggV3UsdOracle_StalePrice(address asset);

// @title AggV3UsdOracle
contract AggV3UsdOracle is IOracle {
    using Math for uint256;

    address public immutable ETH;
    address public immutable ASSET;
    address public immutable ETH_FEED;
    address public immutable ASSET_FEED;
    uint256 public immutable ETH_FEED_DECIMALS;
    uint256 public immutable ASSET_FEED_DECIMALS;
    uint256 public immutable ASSET_DECIMALS;
    bool public immutable ETH_CHECK_TIMESTAMP;
    bool public immutable ASSET_CHECK_TIMESTAMP;
    uint256 public immutable ETH_STALE_PRICE_THRESHOLD;
    uint256 public immutable ASSET_STALE_PRICE_THRESHOLD;

    constructor(
        address eth,
        address asset,
        address ethFeed,
        address assetFeed,
        uint256 ethFeedDecimals,
        uint256 assetFeedDecimals,
        uint256 assetDecimals,
        bool ethCheckTimestamp,
        bool assetCheckTimestamp,
        uint256 ethStalePriceThreshold,
        uint256 assetStalePriceThreshold
    ) {
        ETH = eth;
        ASSET = asset;
        ETH_FEED = ethFeed;
        ASSET_FEED = assetFeed;
        ETH_FEED_DECIMALS = ethFeedDecimals;
        ASSET_FEED_DECIMALS = assetFeedDecimals;
        ASSET_DECIMALS = assetDecimals;
        ETH_CHECK_TIMESTAMP = ethCheckTimestamp;
        ASSET_CHECK_TIMESTAMP = assetCheckTimestamp;
        ETH_STALE_PRICE_THRESHOLD = ethStalePriceThreshold;
        ASSET_STALE_PRICE_THRESHOLD = assetStalePriceThreshold;
    }

    function getValueInEth(address, uint256 amt) external view returns (uint256 value) {
        uint256 ethUsdPrice =
            _getPrice(ETH_FEED, ETH_CHECK_TIMESTAMP, ETH_STALE_PRICE_THRESHOLD, ETH_FEED_DECIMALS, ETH);
        uint256 assetUsdPrice =
            _getPrice(ASSET_FEED, ASSET_CHECK_TIMESTAMP, ASSET_STALE_PRICE_THRESHOLD, ASSET_FEED_DECIMALS, ASSET);

        // scale amt to 18 decimals
        uint256 scaledAmt = amt;
        if (ASSET_DECIMALS < 18) scaledAmt = amt * (10 ** (18 - ASSET_DECIMALS));
        if (ASSET_DECIMALS > 18) scaledAmt = amt / (10 ** (ASSET_DECIMALS - 18));

        return scaledAmt.mulDiv(assetUsdPrice, ethUsdPrice);
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

        if (checkTimestamp) {
            if (updatedAt < block.timestamp - stalePriceThreshold) revert AggV3UsdOracle_StalePrice(asset);
        }

        scaledPrice = uint256(answer);
        if (feedDecimals < 18) scaledPrice = scaledPrice * (10 ** (18 - feedDecimals));
        if (feedDecimals > 18) scaledPrice = scaledPrice / (10 ** (feedDecimals - 18));
    }
}
