// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IOracle } from "../interfaces/IOracle.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

// @title MetaPriceOracle
// @notice General purpose Meta Price Oracle for chaining price feeds
contract MetaPriceOracle is IOracle {
    using Math for uint256;

    IOracle public immutable A;
    IOracle public immutable B;
    IOracle public immutable C;

    constructor(IOracle a, IOracle b, IOracle c) {
        A = a;
        B = b;
        C = c;
    }

    function getValueInEth(address addr, uint256 amt) external view returns (uint256 value) {
        uint256 valueA = address(A) == address(0) ? 1e18 : A.getValueInEth(addr, amt);
        uint256 valueB = address(B) == address(0) ? 1e18 : B.getValueInEth(addr, amt);
        uint256 valueC = address(C) == address(0) ? 1e18 : C.getValueInEth(addr, amt);

        value = valueA.mulDiv(valueB, valueC);
    }
}
