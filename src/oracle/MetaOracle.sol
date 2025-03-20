// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IOracle } from "../interfaces/IOracle.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

// @title MetaOracle
// @notice General purpose MetaOracle for chaining price feeds
contract MetaOracle is IOracle {
    using Math for uint256;

    uint256 public constant WAD = 1e18;

    uint256 public immutable ASSET_DECIMALS;

    IOracle public immutable A;
    IOracle public immutable B;
    IOracle public immutable C;

    address public immutable FEED_ASSET_A;
    address public immutable FEED_ASSET_B;
    address public immutable FEED_ASSET_C;

    uint256 public immutable FEED_DECIMALS_B;
    uint256 public immutable FEED_DECIMALS_A;
    uint256 public immutable FEED_DECIMALS_C;

    constructor(
        address a,
        address b,
        address c,
        address feedAssetA,
        address feedAssetB,
        address feedAssetC,
        uint256 assetDecimals,
        uint256 feedDecimalsA,
        uint256 feedDecimalsB,
        uint256 feedDecimalsC
    ) {
        A = IOracle(a);
        B = IOracle(b);
        C = IOracle(c);

        FEED_ASSET_A = feedAssetA;
        FEED_ASSET_B = feedAssetB;
        FEED_ASSET_C = feedAssetC;

        ASSET_DECIMALS = assetDecimals;

        FEED_DECIMALS_A = feedDecimalsA;
        FEED_DECIMALS_B = feedDecimalsB;
        FEED_DECIMALS_C = feedDecimalsC;
    }

    function getValueInEth(address, uint256 amt) external view returns (uint256 value) {
        // Fetch individual feed prices
        uint256 valueA = address(A) == address(0) ? WAD : A.getValueInEth(FEED_ASSET_A, 10 ** FEED_DECIMALS_A);
        uint256 valueB = address(B) == address(0) ? WAD : B.getValueInEth(FEED_ASSET_B, 10 ** FEED_DECIMALS_B);
        uint256 valueC = address(C) == address(0) ? WAD : C.getValueInEth(FEED_ASSET_C, 10 ** FEED_DECIMALS_C);

        // Scale amt to 18 decimals
        uint256 scaledAmt = amt;
        if (ASSET_DECIMALS < 18) scaledAmt = amt * (10 ** (18 - ASSET_DECIMALS));
        if (ASSET_DECIMALS > 18) scaledAmt = amt / (10 ** (ASSET_DECIMALS - 18));

        value = scaledAmt.mulDiv(valueA.mulDiv(valueB, WAD), valueC);
    }
}
