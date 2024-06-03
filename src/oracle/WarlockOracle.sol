// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        WarlockOracle
//////////////////////////////////////////////////////////////*/

import { IOracle } from "../interfaces/IOracle.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IDataFeed {
    struct PriceData {
        uint128 calculatedTimestamp;
        uint128 submittedTimestamp;
        uint256 price;
        address asset;
        address base;
    }

    function getRecentPrice(address asset, address base) external view returns (PriceData memory);
}

contract WarlockOracle is IOracle {
    using Math for uint256;

    /// @notice Prices older than the stale price threshold are considered invalid
    uint256 public constant STALE_PRICE_THRESHOLD = 3600; // 1 hour

    /// @notice Canonical ETH address
    address public immutable ETH;
    /// @notice Warlock Data Feed
    IDataFeed public immutable DATA_FEED;

    /// @notice Last price update for `asset` was before the accepted stale price threshold
    error WarlockOracle_StalePrice(address asset);

    /// @param eth Canonical ETH address
    /// @param dataFeed Warlock Data Feed
    constructor(address eth, address dataFeed) {
        ETH = eth;
        DATA_FEED = IDataFeed(dataFeed);
    }

    /// @notice Compute the equivalent ETH value for a given amount of a particular asset
    /// @param asset Address of the asset to be priced
    /// @param amt Amount of the given asset to be priced
    function getValueInEth(address asset, uint256 amt) external view returns (uint256) {
        IDataFeed.PriceData memory data = DATA_FEED.getRecentPrice(asset, ETH);

        if (data.submittedTimestamp < block.timestamp - STALE_PRICE_THRESHOLD) revert WarlockOracle_StalePrice(asset);

        amt = _scaleTo18Decimals(asset, amt);
        return amt.mulDiv(data.price, 1e18);
    }

    function _scaleTo18Decimals(address asset, uint256 amt) internal view returns (uint256) {
        uint256 decimals = IERC20Metadata(asset).decimals();
        if (decimals <= 18) return amt * (10 ** (18 - decimals));
        else return amt / (10 ** (decimals - 18));
    }
}
