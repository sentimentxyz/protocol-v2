// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import {Pool} from "../Pool.sol";
import {Position} from "../Position.sol";
import {PositionManager} from "../PositionManager.sol";
import {IRateModel} from "src/interfaces/IRateModel.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// contracts
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import { console } from "forge-std/console.sol";

/*//////////////////////////////////////////////////////////////
                        PortfolioLens
//////////////////////////////////////////////////////////////*/

contract PortfolioLens {
    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/
    Pool public immutable POOL;
    PositionManager public immutable POSITION_MANAGER;

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor(address pool_, address positionManager_) {
        POOL = Pool(pool_);
        POSITION_MANAGER = PositionManager(positionManager_);
    }
    /*//////////////////////////////////////////////////////////////
                             Data Structs
    //////////////////////////////////////////////////////////////*/

    struct AssetData {
        address asset;
        uint256 amount;
    }

    struct DebtData {
        uint256 poolId;
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
        address[] memory assets = Position(position).getPositionAssets();
        AssetData[] memory assetData = new AssetData[](assets.length);

        for (uint256 i; i < assets.length; ++i) {
            assetData[i] = AssetData({asset: assets[i], amount: IERC20(assets[i]).balanceOf(position)});
        }

        return assetData;
    }

    function getDebtData(address position) public view returns (DebtData[] memory) {
        uint256[] memory debtPools = Position(position).getDebtPools();
        DebtData[] memory debtData = new DebtData[](debtPools.length);

        for (uint256 i; i < debtPools.length; ++i) {
            uint256 poolId = debtPools[i];
            uint256 borrows = POOL.getTotalBorrows(poolId);
            uint256 idleAmt; // TODO

            DebtData({
                poolId: poolId,
                asset: POOL.getPoolAssetFor(poolId),
                amount: POOL.getBorrowsOf(poolId, position),
                interestRate: IRateModel(POOL.getRateModelFor(poolId)).getInterestRate(borrows, idleAmt)
            });
        }

        return debtData;
    }

    function predictAddress(address owner, bytes32 salt) external view returns (address, bool) {
        salt = keccak256(abi.encodePacked(owner, salt));

        bytes memory creationCode =
            abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(address(POSITION_MANAGER.positionBeacon()), ""));

        address predictedAddress = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), POSITION_MANAGER, salt, keccak256(creationCode)))))
        );

        return (predictedAddress, predictedAddress.code.length == 0);
    }
}
