// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IOracle } from "../interfaces/IOracle.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

interface ISystemOracle {
    function markPx(uint16 index) external view returns (uint64 price);
}

/// @title HlUsdcOracle
/// @notice Oracle implementation to price assets using ETH-denominated Hyperliquid feeds
contract HlUsdcOracle is IOracle {
    using Math for uint256;

    uint16 public constant ETH_INDEX = 4;
    uint256 public constant ETH_PRICE_SCALE = 1e16;
    uint256 public constant ASSET_AMT_SCALE = 1e12;
    ISystemOracle public constant SYSTEM_ORACLE = ISystemOracle(0x0000000000000000000000000000000000000806);

    function getValueInEth(address, uint256 amt) external view returns (uint256) {
        uint256 assetAmt = amt * ASSET_AMT_SCALE;
        uint256 ethPrice = SYSTEM_ORACLE.markPx(ETH_INDEX) * ETH_PRICE_SCALE;

        return assetAmt.mulDiv(1e18, ethPrice);
    }
}
