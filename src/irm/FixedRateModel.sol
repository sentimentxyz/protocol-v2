// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import { IRateModel } from "../interfaces/IRateModel.sol";
// libraries
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/*//////////////////////////////////////////////////////////////
                        FixedRateModel
//////////////////////////////////////////////////////////////*/

contract FixedRateModel is IRateModel {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    // 18 decimal scaled fixed APR
    uint256 public immutable RATE;

    // 1 year = 365.25 days
    uint256 constant SECONDS_PER_YEAR = 31_557_600;

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor(uint256 rate) {
        // store fixed rate as immutable constant
        RATE = rate;
    }

    /*//////////////////////////////////////////////////////////////
                        Public View Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice calculate the interest accrued since the last update
    /// @param lastUpdated timestamp for the last update
    /// @param borrows the total amount of borrows, denominated in notional asset units
    /// @return interest notional amount of interest accrued since the last update
    function interestAccrued(uint256 lastUpdated, uint256 borrows, uint256) external view returns (uint256 interest) {
        // rateFactor = time delta * apr / secs_per_year
        // [ROUND] rateFactor is rounded up, in favor of the protocol
        uint256 rateFactor = ((block.timestamp - lastUpdated)).mulDiv(RATE, SECONDS_PER_YEAR, Math.Rounding.Up);

        // interest accrued = borrows * rateFactor
        // [ROUND] interest accrued is rounded up, in favor of the protocol
        return borrows.mulDiv(rateFactor, 1e18, Math.Rounding.Up);
    }

    function getInterestRate(uint256, uint256) external view returns (uint256) {
        return RATE;
    }
}
