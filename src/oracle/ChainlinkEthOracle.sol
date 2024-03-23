// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {IOracle} from "../interface/IOracle.sol";
import {IAggegregatorV3} from "../interface/IAggregatorV3.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
// contracts
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ChainlinkEthOracle is Ownable {
    using Math for uint256;

    event FeedSet(address indexed asset, address feed);

    // asset/eth price feed
    mapping(address asset => address feed) public priceFeedFor;

    constructor(address owner) Ownable(owner) {}

    function getValueInEth(address asset, uint256 amt) external view returns (uint256) {
        (, int256 price,,,) = IAggegregatorV3(priceFeedFor[asset]).latestRoundData();

        // [ROUND] price is rounded down. this is used for both debt and asset math, no effect
        return amt.mulDiv(uint256(price), (10 ** IERC20Metadata(asset).decimals()));
    }

    function setFeed(address asset, address feed) external onlyOwner {
        assert(IAggegregatorV3(feed).decimals() == 18);
        priceFeedFor[asset] = feed;

        emit FeedSet(asset, feed);
    }
}
