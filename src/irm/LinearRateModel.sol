// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {IRateModel} from "../interfaces/IRateModel.sol";
// libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract LinearRateModel is IRateModel {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    uint256 public immutable MIN_RATE; // 18 decimal scaled APR
    uint256 public immutable MAX_RATE; // 18 decimal scaled APR
    uint256 immutable RATE_DIFF; // MAX_RATE - MIN_RATE
    uint256 constant SECONDS_PER_YEAR = 31_557_600; // 1 year = 365.25 days

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor(uint256 minRate, uint256 maxRate) {
        assert(maxRate > minRate);
        MIN_RATE = minRate;
        MAX_RATE = maxRate;
        RATE_DIFF = maxRate - minRate;
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    function getInterestRate(uint256 borrows, uint256 idleAmt) public view returns (uint256) {
        // util = borrows / (borrows + idleAmt)
        uint256 util = borrows.mulDiv(1e18, borrows + idleAmt, Math.Rounding.Ceil);

        // interest rate = MIN_RATE + util * (MAX_RATE - MIN_RATE)
        return MIN_RATE + util.mulDiv(RATE_DIFF, 1e18, Math.Rounding.Ceil);
    }

    /// @notice calculates the interest accrued since the last update
    /// @param lastUpdated the timestamp of the last update
    /// @param borrows the total amount of borrows
    /// @return interest accrued since the last update
    function interestAccrued(uint256 lastUpdated, uint256 borrows, uint256 idleAmt) external view returns (uint256) {
        // rateFactor = time delta * apr / secs_per_year
        // rate is scaled but time delta and seconds_per_year are not scaled, to preserve precision
        uint256 rateFactor = ((block.timestamp - lastUpdated)).mulDiv(
            getInterestRate(borrows, idleAmt), SECONDS_PER_YEAR, Math.Rounding.Ceil
        );

        // interest accrued = borrows * rateFactor
        return borrows.mulDiv(rateFactor, 1e18, Math.Rounding.Ceil);
    }
}
