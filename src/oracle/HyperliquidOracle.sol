// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IOracle } from "../interfaces/IOracle.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

interface ISystemOracle {
    function markPx(uint16 index) external view returns (uint64 price);
}

/// @title HyperliquidOracle
/// @notice Oracle implementation to price assets using ETH-denominated Hyperliquid feeds
contract HyperliquidOracle is IOracle {
    using Math for uint256;

    uint16 public constant ETH_INDEX = 4;
    uint256 public constant ETH_PRICE_SCALE = 1e16;
    ISystemOracle public constant SYSTEM_ORACLE = ISystemOracle(0x0000000000000000000000000000000000000806);

    address public immutable ASSET;
    uint16 public immutable ASSET_INDEX;
    uint256 public immutable ASSET_AMT_SCALE;
    uint256 public immutable ASSET_PRICE_SCALE;

    error HyperLiquidOracle_InvalidAsset(address, address);

    constructor(address asset, uint16 assetIndex, uint256 assetAmtScale, uint256 assetPriceScale) {
        ASSET = asset;
        ASSET_INDEX = assetIndex;
        ASSET_AMT_SCALE = assetAmtScale;
        ASSET_PRICE_SCALE = assetPriceScale;
    }

    function getValueInEth(address asset, uint256 amt) external view returns (uint256) {
        if (asset != ASSET) revert HyperLiquidOracle_InvalidAsset(asset, ASSET);

        uint256 assetAmt = amt * ASSET_AMT_SCALE;
        uint256 ethPrice = SYSTEM_ORACLE.markPx(ETH_INDEX) * ETH_PRICE_SCALE;
        uint256 assetPrice = SYSTEM_ORACLE.markPx(ASSET_INDEX) * ASSET_PRICE_SCALE;

        return assetAmt.mulDiv(assetPrice, ethPrice);
    }
}
