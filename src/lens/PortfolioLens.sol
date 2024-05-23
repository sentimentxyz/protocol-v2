// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import {Pool} from "../Pool.sol";
import {Position} from "../Position.sol";
import {RiskEngine} from "../RiskEngine.sol";
import {IOracle} from "src/interfaces/IOracle.sol";
import {PositionManager} from "../PositionManager.sol";
import {IRateModel} from "src/interfaces/IRateModel.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// contracts
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {console} from "forge-std/console.sol";

/*//////////////////////////////////////////////////////////////
                        PortfolioLens
//////////////////////////////////////////////////////////////*/

contract PortfolioLens {
    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/
    Pool public immutable POOL;
    RiskEngine public immutable RISK_ENGINE;
    PositionManager public immutable POSITION_MANAGER;

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor(address pool_, address riskEngine_, address positionManager_) {
        POOL = Pool(pool_);
        RISK_ENGINE = RiskEngine(riskEngine_);
        POSITION_MANAGER = PositionManager(positionManager_);
    }
    /*//////////////////////////////////////////////////////////////
                             Data Structs
    //////////////////////////////////////////////////////////////*/

    struct AssetData {
        address asset;
        uint256 amount;
        uint256 valueInEth;
    }

    struct DebtData {
        uint256 poolId;
        address asset;
        uint256 amount;
        uint256 valueInEth;
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
            address asset = assets[i];
            uint256 amount = IERC20(assets[i]).balanceOf(position);
            assetData[i] = AssetData({asset: asset, amount: amount, valueInEth: _getValueInEth(asset, amount)});
        }

        return assetData;
    }

    function getDebtData(address position) public view returns (DebtData[] memory) {
        uint256[] memory debtPools = Position(position).getDebtPools();
        DebtData[] memory debtData = new DebtData[](debtPools.length);

        for (uint256 i; i < debtPools.length; ++i) {
            uint256 poolId = debtPools[i];
            address poolAsset = POOL.getPoolAssetFor(poolId);
            uint256 totalBorrows = POOL.getTotalBorrows(poolId);
            uint256 idleAmt = POOL.getTotalAssets(poolId) - totalBorrows;
            uint256 borrowAmt = POOL.getBorrowsOf(poolId, position);

            debtData[i] = DebtData({
                poolId: poolId,
                asset: poolAsset,
                amount: borrowAmt,
                valueInEth: _getValueInEth(poolAsset, borrowAmt),
                interestRate: IRateModel(POOL.getRateModelFor(poolId)).getInterestRate(totalBorrows, idleAmt)
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

    function _getValueInEth(address asset, uint256 amt) internal view returns (uint256) {
        IOracle oracle = IOracle(RISK_ENGINE.getOracleFor(asset));

        // oracles could revert, lens calls must not
        try oracle.getValueInEth(asset, amt) returns (uint256 valueInEth) {
            return valueInEth;
        } catch {
            return 0;
        }
    }
}
