// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IOracle } from "../interfaces/IOracle.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { L1Read } from "src/lib/L1Read.sol";

/// @title HyperliquidOracle
/// @notice Oracle implementation to price assets using ETH-denominated Hyperliquid feeds
contract HyperliquidOracle is L1Read, IOracle {
    using Math for uint256;

    uint32 public constant ETH_INDEX = 1;
    uint256 public constant ETH_PRICE_SCALE = 1e16;

    address public immutable ASSET;
    uint32 public immutable ASSET_INDEX;
    uint256 public immutable ASSET_AMT_SCALE;
    uint256 public immutable ASSET_PRICE_SCALE;

    error HlOracle_InvalidAsset(address, address);

    constructor(address asset, uint32 assetIndex, uint256 assetAmtScale, uint256 assetPriceScale) {
        ASSET = asset;
        ASSET_INDEX = assetIndex;
        ASSET_AMT_SCALE = assetAmtScale;
        ASSET_PRICE_SCALE = assetPriceScale;
    }

    function getValueInEth(address asset, uint256 amt) external view returns (uint256) {
        if (asset != ASSET) revert HlOracle_InvalidAsset(asset, ASSET);

        uint256 assetAmt = amt * ASSET_AMT_SCALE;
        uint256 ethPrice = markPx(ETH_INDEX) * ETH_PRICE_SCALE;
        uint256 assetPrice = markPx(ASSET_INDEX) * ASSET_PRICE_SCALE;

        return assetAmt.mulDiv(assetPrice, ethPrice);
    }
}
