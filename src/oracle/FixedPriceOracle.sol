// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {IOracle} from "../interfaces/IOracle.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console2} from "forge-std/console2.sol"; // TODO remove console2

contract FixedPriceOracle {
    using Math for uint256;

    uint256 public immutable PRICE;

    constructor(uint256 price) {
        PRICE = price;
    }

    function getValueInEth(address asset, uint256 amt) external view returns (uint256) {
        // value = amt * price % asset.decimals()
        // console2.log("--FP OR--");
        // console2.log("asset", asset);
        // console2.log("amt", amt);
        // console2.log("price", PRICE);
        // console2.log("decimals", IERC20Metadata(asset).decimals());
        // console2.log("answer", amt.mulDiv(PRICE, (10 ** IERC20Metadata(asset).decimals())));
        // console2.log("----");
        return amt.mulDiv(PRICE, (10 ** IERC20Metadata(asset).decimals()));
    }
}
