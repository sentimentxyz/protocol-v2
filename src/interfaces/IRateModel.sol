// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IRateModel {
    function rateFactor(uint256 lastKnownTimestamp) external view returns (uint256);
}
