// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {IOracle} from "../interface/IOracle.sol";
import {IAggegregatorV3} from "../interface/IAggregatorV3.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// libraries
import {Errors} from "../lib/Errors.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
// contracts
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ChainlinkEthOracle is Ownable {
    using Math for uint256;

    event FeedSet(address indexed asset, address feed);

    // sequencer grace period
    uint256 public constant SEQ_GRACE_PERIOD = 3600; // 60 * 60 secs -> 1 hour

    // stale price threshold, prices older than this period are considered stale
    // the oracle can misreport stale prices for feeds with longer hearbeats
    uint256 public constant STALE_PRICE_THRESHOLD = 3600; // 60 * 60 secs -> 1 hour

    // Arbitrum sequencer feed
    IAggegregatorV3 public immutable ARB_SEQ_FEED;

    // asset/eth price feed
    mapping(address asset => address feed) public priceFeedFor;

    constructor(address owner, address arbSeqFeed) Ownable(owner) {
        ARB_SEQ_FEED = IAggegregatorV3(arbSeqFeed);
    }

    function getValueInEth(address asset, uint256 amt) external view returns (uint256) {
        _checkSequencerFeed();

        return amt.mulDiv(_getPriceWithSanityChecks(asset), (10 ** IERC20Metadata(asset).decimals()));
    }

    function setFeed(address asset, address feed) external onlyOwner {
        assert(IAggegregatorV3(feed).decimals() == 18);
        priceFeedFor[asset] = feed;

        emit FeedSet(asset, feed);
    }

    function _checkSequencerFeed() private view {
        (, int256 answer, uint256 startedAt,,) = ARB_SEQ_FEED.latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        if (answer != 0) {
            revert Errors.SequencerDown();
        }

        if (block.timestamp - startedAt <= SEQ_GRACE_PERIOD) {
            revert Errors.GracePeriodNotOver();
        }
    }

    function _getPriceWithSanityChecks(address asset) private view returns (uint256) {
        (, int256 price,, uint256 updatedAt,) = IAggegregatorV3(priceFeedFor[asset]).latestRoundData();

        if (price < 0) revert Errors.NegativePrice();
        if (updatedAt < block.timestamp - STALE_PRICE_THRESHOLD) revert Errors.StalePrice();

        return uint256(price);
    }
}
