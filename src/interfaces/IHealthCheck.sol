// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IHealthCheck {
    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    function TYPE() external view returns (uint256 positionType);
    function isPositionHealthy(address) external view returns (bool isHealthy);
}
