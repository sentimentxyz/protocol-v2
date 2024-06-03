// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import { IOracle } from "../interfaces/IOracle.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// libraries
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
// contracts
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

interface IAggegregatorV3 {
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function decimals() external view returns (uint256);
}

contract ChainlinkUsdOracle is Ownable {
    using Math for uint256;

    // internal alias for native ETH
    address private constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // sequencer grace period
    uint256 public constant SEQ_GRACE_PERIOD = 3600; // 60 * 60 secs -> 1 hour

    // stale price threshold, prices older than this period are considered stale
    // the oracle can misreport stale prices for feeds with longer hearbeats
    uint256 public constant STALE_PRICE_THRESHOLD = 3600; // 60 * 60 secs -> 1 hour

    IAggegregatorV3 public immutable ARB_SEQ_FEED; // Arbitrum sequencer feed
    IAggegregatorV3 public immutable ETH_USD_FEED; // ETH/USD price feed

    event FeedSet(address indexed asset, address feed);

    // asset/eth price feed
    mapping(address asset => address feed) public priceFeedFor;

    /*//////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/

    error ChainlinkUsdOracle_SequencerDown();
    error ChainlinkUsdOracle_GracePeriodNotOver();
    error ChainlinkUsdOracle_StalePrice(address asset);
    error ChainlinkUsdOracle_NegativePrice(address asset);

    constructor(address owner, address arbSeqFeed, address ethUsdFeed) Ownable() {
        ARB_SEQ_FEED = IAggegregatorV3(arbSeqFeed);
        ETH_USD_FEED = IAggegregatorV3(ethUsdFeed);
        priceFeedFor[ETH] = ethUsdFeed;

        _transferOwnership(owner);
    }

    function getValueInEth(address asset, uint256 amt) external view returns (uint256) {
        _checkSequencerFeed();

        uint256 ethUsdPrice = _getPriceWithSanityChecks(ETH);
        uint256 assetUsdPrice = _getPriceWithSanityChecks(asset);

        uint256 decimals = IERC20Metadata(asset).decimals();

        // [ROUND] price is rounded down. this is used for both debt and asset math, no effect
        if (decimals <= 18) {
            return (amt * 10 ** (18 - decimals)).mulDiv(uint256(assetUsdPrice), uint256(ethUsdPrice));
        } else {
            return (amt / (10 ** decimals - 18)).mulDiv(uint256(assetUsdPrice), uint256(ethUsdPrice));
        }
    }

    function setFeed(address asset, address feed) external onlyOwner {
        assert(IAggegregatorV3(feed).decimals() == 8);
        priceFeedFor[asset] = feed;

        emit FeedSet(asset, feed);
    }

    function _checkSequencerFeed() private view {
        (, int256 answer, uint256 startedAt,,) = ARB_SEQ_FEED.latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        if (answer != 0) {
            revert ChainlinkUsdOracle_SequencerDown();
        }

        if (block.timestamp - startedAt <= SEQ_GRACE_PERIOD) {
            revert ChainlinkUsdOracle_GracePeriodNotOver();
        }
    }

    function _getPriceWithSanityChecks(address asset) private view returns (uint256) {
        (, int256 price,, uint256 updatedAt,) = IAggegregatorV3(priceFeedFor[asset]).latestRoundData();

        if (price < 0) revert ChainlinkUsdOracle_NegativePrice(asset);
        if (updatedAt < block.timestamp - STALE_PRICE_THRESHOLD) revert ChainlinkUsdOracle_StalePrice(asset);

        return uint256(price);
    }
}
