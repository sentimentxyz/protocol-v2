// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IOracle } from "../interfaces/IOracle.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

// @title MetaOracle
// @notice General purpose MetaOracle for chaining price feeds
contract MetaOracle is IOracle {
    using Math for uint256;

    IOracle public immutable A;
    IOracle public immutable B;
    IOracle public immutable C;

    uint256 public immutable WAD = 1e18;
    uint256 public immutable ASSET_DECIMALS;
    uint256 public immutable FEED_DECIMALS_A;
    uint256 public immutable FEED_DECIMALS_B;
    uint256 public immutable FEED_DECIMALS_C;

    constructor(
        IOracle a,
        IOracle b,
        IOracle c,
        uint256 assetDecimals,
        uint256 feedDecimalsA,
        uint256 feedDecimalsB,
        uint256 feedDecimalsC
    ) {
        A = a;
        B = b;
        C = c;
        ASSET_DECIMALS = assetDecimals;
        FEED_DECIMALS_A = feedDecimalsA;
        FEED_DECIMALS_B = feedDecimalsB;
        FEED_DECIMALS_C = feedDecimalsC;
    }

    function getValueInEth(address asset, uint256 amt) external view returns (uint256 value) {
        uint256 valueA = address(A) == address(0) ? WAD : A.getValueInEth(asset, 10 ** FEED_DECIMALS_A);
        uint256 valueB = address(B) == address(0) ? WAD : B.getValueInEth(asset, 10 ** FEED_DECIMALS_B);
        uint256 valueC = address(C) == address(0) ? WAD : C.getValueInEth(asset, 10 ** FEED_DECIMALS_C);

        value = amt.mulDiv(valueA.mulDiv(valueB, valueC), 10 ** ASSET_DECIMALS);
    }
}
