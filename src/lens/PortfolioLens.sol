// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {Pool} from "./Pool.sol";
import {PositionManager} from "./PositionManager.sol";
import {IPosition} from "src/interfaces/IPosition.sol";
import {IRateModel} from "src/interfaces/IRateModel.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PortfolioLens {
    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/
    PositionManager immutable POSITION_MANAGER;

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor(address positionManager) {
        POSITION_MANAGER = PositionManager(positionManager);
    }
    /*//////////////////////////////////////////////////////////////
                             Data Structs
    //////////////////////////////////////////////////////////////*/

    struct AssetData {
        address asset;
        uint256 amount;
    }

    struct DebtData {
        address pool;
        address asset;
        uint256 amount;
        uint256 interestRate;
    }

    struct PositionData {
        address position;
        address owner;
        AssetData[] assets;
        DebtData[] debts;
    }

    struct PortfolioData {
        PositionData[] positions;
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    function getPortfolioData(address[] calldata positions) public view returns (PortfolioData memory) {
        PositionData[] memory positionData = new PositionData[](positions.length);

        for (uint256 i; i < positions.length; ++i) {
            positionData[i] = getPositionData(positions[i]);
        }

        return PortfolioData({positions: positionData});
    }

    function getPositionData(address position) public view returns (PositionData memory) {
        return PositionData({
            position: position,
            owner: POSITION_MANAGER.ownerOf(position),
            assets: getAssetData(position),
            debts: getDebtData(position)
        });
    }

    function getAssetData(address position) public view returns (AssetData[] memory) {
        address[] memory assets = IPosition(position).getAssets();
        AssetData[] memory assetData = new AssetData[](assets.length);

        for (uint256 i; i < assets.length; ++i) {
            assetData[i] = AssetData({asset: assets[i], amount: IERC20(assets[i]).balanceOf(position)});
        }

        return assetData;
    }

    function getDebtData(address position) public view returns (DebtData[] memory) {
        address[] memory debtPools = IPosition(position).getDebtPools();
        DebtData[] memory debtData = new DebtData[](debtPools.length);

        for (uint256 i; i < debtPools.length; ++i) {
            Pool debtPool = Pool(debtPools[i]);
            address debtAsset = debtPool.asset();
            uint256 borrows = debtPool.getBorrows();
            uint256 idleAmt = IERC20(debtAsset).balanceOf(debtPools[i]);

            DebtData({
                pool: debtPools[i],
                asset: debtAsset,
                amount: debtPool.getBorrowsOf(position),
                interestRate: debtPool.rateModel().getInterestRate(borrows, idleAmt)
            });
        }

        return debtData;
    }
}
