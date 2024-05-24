// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRateModel {
    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/
    function interestAccrued(uint256 lastUpdated, uint256 borrows, uint256 idleAssetAmt) external view returns (uint256 interest);

    function getInterestRate(uint256 borrows, uint256 idleAssetAmt) external view returns (uint256 interestRate);
}
