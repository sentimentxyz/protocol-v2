// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtData, AssetData} from "../PositionManager.sol";

interface IHealthCheck {
    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    function TYPE() external view returns (uint256 positionType);
    function isPositionHealthy(address position) external view returns (bool isHealthy);
    function isValidLiquidation(
        address position,
        DebtData[] calldata debt,
        AssetData[] calldata collat,
        uint256 liquidationDiscount
    ) external view returns (bool isValid);
}
