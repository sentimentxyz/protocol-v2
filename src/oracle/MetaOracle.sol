// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IOracle } from "../interfaces/IOracle.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

// @title MetaOracle
// @notice General purpose Meta Oracle for chaining price feeds
contract MetaOracle is IOracle {
    using Math for uint256;

    IOracle public immutable A;
    IOracle public immutable B;
    IOracle public immutable C;

    uint256 public immutable WAD = 1e18;
    uint256 public immutable ASSET_DECIMALS;

    constructor(IOracle a, IOracle b, IOracle c, uint256 assetDecimals) {
        A = a;
        B = b;
        C = c;
        ASSET_DECIMALS = assetDecimals;
    }

    function getValueInEth(address asset, uint256 amt) external view returns (uint256 value) {
        uint256 valueA = address(A) == address(0) ? 1e18 : A.getValueInEth(asset, WAD);
        uint256 valueB = address(B) == address(0) ? 1e18 : B.getValueInEth(asset, WAD);
        uint256 valueC = address(C) == address(0) ? 1e18 : C.getValueInEth(asset, WAD);

        value = valueA.mulDiv(valueB, valueC);
        value = amt.mulDiv(value, ASSET_DECIMALS);
    }
}
