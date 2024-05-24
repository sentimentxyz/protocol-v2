// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import { IOracle } from "../interfaces/IOracle.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// libraries
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract FixedPriceOracle {
    using Math for uint256;

    uint256 public immutable PRICE;

    constructor(uint256 price) {
        PRICE = price;
    }

    function getValueInEth(address asset, uint256 amt) external view returns (uint256) {
        // value = amt * price % asset.decimals()
        // [ROUND] price is rounded down. this is used for both debt and asset math, no effect
        return amt.mulDiv(PRICE, (10 ** IERC20Metadata(asset).decimals()));
    }
}
