// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtData, AssetData} from "../PositionManager.sol";

interface IRiskModule {
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

    function getRiskData(address position)
        external
        view
        returns (uint256 totalAssetsInEth, uint256 totalDebtInEth, uint256 minAssetsRequiredInEth);

    function getDebtValue(address position, address pool, uint256 amt) external returns (uint256 debtValueInEth);
    function getTotalDebtValue(address position) external view returns (uint256 totalDebtInEth);

    function getTotalAssetValue(address position) external view returns (uint256 totalAssetsInEth);
    function getAssetValue(address position, address asset, uint256 amt) external returns (uint256 assetValueInEth);
}
