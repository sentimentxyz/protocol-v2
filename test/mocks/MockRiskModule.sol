// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        MockRiskModule
//////////////////////////////////////////////////////////////*/

// types
import {RiskModule} from "src/RiskModule.sol";
import {Position} from "src/Position.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title RiskModule
contract MockRiskModule is RiskModule {
    using Math for uint256;

    constructor(
        address registry_,
        uint256 minDebt_,
        uint256 liquidationDiscount_
    ) RiskModule(registry_, minDebt_, liquidationDiscount_) {}

    function getFutureAssetValue(
        address payable position,
        address asset,
        uint256 newAssetValue
    ) external view returns (uint256, address[] memory, uint256[] memory) {
        uint256 totalAssetValue;

        address[] memory positionAssets = Position(position)
            .getPositionAssets();
        uint256 positionAssetsLength = positionAssets.length;
        uint256[] memory positionAssetData = new uint256[](
            positionAssetsLength
        );

        for (uint256 i; i < positionAssetsLength; ++i) {
            uint256 assets = getAssetValue(position, positionAssets[i]);
            // positionAssetData[i] stores value of positionAssets[i] in eth
            if (asset == positionAssets[i]) {
                positionAssetData[i] = assets;
                totalAssetValue += assets;
                totalAssetValue += newAssetValue;
            } else {
                positionAssetData[i] = assets;
                totalAssetValue += assets;
            }
        }

        if (totalAssetValue == 0) return (0, positionAssets, positionAssetData);

        for (uint256 i; i < positionAssetsLength; ++i) {
            // positionAssetData[i] stores weight of positionAsset[i]
            // wt of positionAsset[i] = (value of positionAsset[i]) / (total position assets value)
            positionAssetData[i] = positionAssetData[i].mulDiv(
                1e18,
                totalAssetValue
            );
        }

        return (totalAssetValue, positionAssets, positionAssetData);
    }

    function getAssetValue(
        address position
    ) external view returns (uint256, address[] memory, uint256[] memory) {
        (
            uint256 totalAssetValue,
            address[] memory positionAssets,
            uint256[] memory positionAssetData
        ) = _getPositionAssetData(position);
        return (totalAssetValue, positionAssets, positionAssetData);
    }

    function getFutureDebtValue(
        address payable position,
        uint256 poolId,
        uint256 newDebtValue
    ) external view returns (uint256, uint256[] memory, uint256[] memory) {
        uint256 totalDebtValue;
        uint256[] memory debtPools = Position(position).getDebtPools();
        uint256[] memory debtValueForPool = new uint256[](debtPools.length);

        uint256 debtPoolsLength = debtPools.length;
        for (uint256 i; i < debtPoolsLength; ++i) {
            uint256 debt = getDebtValueForPool(position, debtPools[i]);
            if (debtPools[i] == poolId) {
                debtValueForPool[i] = debt + newDebtValue;
                totalDebtValue += debt;
                totalDebtValue += newDebtValue;
            } else {
                debtValueForPool[i] = debt;
                totalDebtValue += debt;
            }
        }

        return (totalDebtValue, debtPools, debtValueForPool);
    }

    function getDebtValue(
        address position
    ) external view returns (uint256, uint256[] memory, uint256[] memory) {
        (
            uint256 totalDebtValue,
            uint256[] memory debtPools,
            uint256[] memory debtValueForPool
        ) = _getPositionDebtData(position);
        return (totalDebtValue, debtPools, debtValueForPool);
    }

    function getMinReqAssetValue(
        uint256[] memory debtPools,
        uint256[] memory debtValuleForPool,
        address[] memory positionAssets,
        uint256[] memory wt,
        address position
    ) external view returns (uint256) {
        return
            _getMinReqAssetValue(
                debtPools,
                debtValuleForPool,
                positionAssets,
                wt,
                position
            );
    }
}
