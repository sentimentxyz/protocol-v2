// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

interface IOracle {
    function getValueInEth(address asset, uint256 amt) external view returns (uint256 value);
}

interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

error AggV3EthOracle_StalePrice(address asset);

// @title AggV3EthOracle
contract AggV3EthOracle is IOracle {
    using Math for uint256;

    address public immutable FEED;
    address public immutable ASSET;
    uint256 public immutable FEED_DECIMALS;
    uint256 public immutable ASSET_DECIMALS;
    bool public immutable CHECK_TIMESTAMP;
    uint256 public immutable STALE_PRICE_THRESHOLD;

    constructor(
        address feed,
        address asset,
        uint256 feedDecimals,
        uint256 assetDecimals,
        bool checkTimestamp,
        uint256 stalePriceThreshold
    ) {
        FEED = feed;
        ASSET = asset;
        FEED_DECIMALS = feedDecimals;
        ASSET_DECIMALS = assetDecimals;
        CHECK_TIMESTAMP = checkTimestamp;
        STALE_PRICE_THRESHOLD = stalePriceThreshold;
    }

    function getValueInEth(address asset, uint256 amt) external view returns (uint256 value) {
        (, int256 answer,, uint256 updatedAt,) = IAggregatorV3(FEED).latestRoundData();

        if (CHECK_TIMESTAMP) {
            if (updatedAt < block.timestamp - STALE_PRICE_THRESHOLD) revert AggV3EthOracle_StalePrice(asset);
        }

        // scale price to 18 decimals, if needed
        uint256 scaledPrice = uint256(answer);
        if (FEED_DECIMALS < 18) scaledPrice = scaledPrice * (10 ** (18 - FEED_DECIMALS));
        if (FEED_DECIMALS > 18) scaledPrice = scaledPrice / (10 ** (FEED_DECIMALS - 18));

        return amt.mulDiv(scaledPrice, (10 ** ASSET_DECIMALS));
    }
}
