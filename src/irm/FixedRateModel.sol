// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        FixedRateModel
//////////////////////////////////////////////////////////////*/

import {IRateModel} from "../interfaces/IRateModel.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title FixedRateModel
/// @notice Rate model implementation with a fixed immutable rate
contract FixedRateModel is IRateModel {
    using Math for uint256;

    /// @notice Number of seconds in a year as per the rate model
    uint256 public constant SECONDS_PER_YEAR = 31_557_600; // 1 year = 365.25 days

    /// @notice Fixed interest rate for the rate model scaled to 18 decimals
    uint256 public immutable RATE;

    /// @param rate Fixed interest rate scaled to 18 decimals
    constructor(uint256 rate) {
        RATE = rate;
    }

    /// @inheritdoc IRateModel
    function getInterestAccrued(uint256 lastUpdated, uint256 totalBorrows, uint256) external view returns (uint256 interestAccrued) {
        // [ROUND] rateFactor is rounded up, in favor of the protocol
        // rateFactor = time delta * apr / secondsPerYear
        uint256 rateFactor = ((block.timestamp - lastUpdated)).mulDiv(RATE, SECONDS_PER_YEAR, Math.Rounding.Ceil);

        // [ROUND] interest accrued is rounded up, in favor of the protocol
        // interestAccrued = borrows * rateFactor
        return totalBorrows.mulDiv(rateFactor, 1e18, Math.Rounding.Ceil);
    }

    /// @inheritdoc IRateModel
    function getInterestRate(uint256, uint256) external view returns (uint256 interestRate) {
        return RATE;
    }
}
