// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// types
import {IRateModel} from "./interfaces/IRateModel.sol";
// libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract FixedRateModel is IRateModel {
    using Math for uint256;

    uint256 public immutable RATE; // 18 decimal scaled APR
    uint256 constant SECONDS_PER_YEAR = 31_557_600e18; // 1 year = 365.25 days

    constructor(uint256 rate) {
        RATE = rate;
    }

    function interestAccrued(uint256 lastUpdated, uint256 borrows, uint256) external view returns (uint256) {
        // rateFactor = time delta * apr / secs_per_year
        uint256 rateFactor = ((block.timestamp - lastUpdated) * 1e18).mulDiv(RATE, SECONDS_PER_YEAR, Math.Rounding.Ceil);

        // interest accrued = borrows * rateFactor
        return borrows.mulDiv(rateFactor, 1e18, Math.Rounding.Ceil);
    }
}
