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

contract ChainlinkUsdOracle is Ownable {
    using Math for uint256;

    IAggegregatorV3 public immutable ETH_USD_FEED;

    // asset/eth price feed
    mapping(address asset => address feed) public priceFeedFor;

    constructor(address ethUsdFeed) Ownable(msg.sender) {
        ETH_USD_FEED = IAggegregatorV3(ethUsdFeed);
    }

    function getValueInEth(address asset, uint256 amt) external view returns (uint256) {
        (, int256 assetUsdPrice,,,) = IAggegregatorV3(priceFeedFor[asset]).latestRoundData();
        (, int256 ethUsdPrice,,,) = ETH_USD_FEED.latestRoundData();

        uint256 decimals = IERC20Metadata(asset).decimals();
        if (decimals <= 18) {
            return (amt * 10 ** (18 - decimals)).mulDiv(uint256(assetUsdPrice), uint256(ethUsdPrice));
        } else {
            return (amt / (10 ** decimals - 18)).mulDiv(uint256(assetUsdPrice), uint256(ethUsdPrice));
        }
    }

    function setFeed(address asset, address feed) external onlyOwner {
        assert(IAggegregatorV3(feed).decimals() == 8);
        priceFeedFor[asset] = feed;
    }
}
