// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IRateModel {
    function interestAccrued(uint256 lastUpdated, uint256 borrows, uint256 idleAmt) external view returns (uint256);
}
