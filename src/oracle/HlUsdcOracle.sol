// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IOracle } from "../interfaces/IOracle.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

interface ISystemOracle {
    function markPxs(uint index) external view returns (uint price);
}

/// @title HlUsdcOracle
/// @notice Oracle implementation to price assets using ETH-denominated Hyperliquid feeds
contract HlUsdcOracle is IOracle {
    using Math for uint256;

    uint public constant ETH_INDEX = 4;
    uint public constant ETH_PRICE_SCALE = 1e16;
    uint public constant ASSET_AMT_SCALE = 1e12;
    ISystemOracle public constant SYSTEM_ORACLE = ISystemOracle(0x1111111111111111111111111111111111111111);

    function getValueInEth(address, uint256 amt) external view returns (uint256) {
        uint assetAmt = amt * ASSET_AMT_SCALE;
        uint ethPrice = SYSTEM_ORACLE.markPxs(ETH_INDEX) * ETH_PRICE_SCALE;

        return assetAmt.mulDiv(1e18, ethPrice);
    }
}
