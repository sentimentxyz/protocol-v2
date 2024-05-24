// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import { Pool } from "../Pool.sol";
import { SuperPool } from "../SuperPool.sol";
import { RiskEngine } from "../RiskEngine.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { IRateModel } from "../interfaces/IRateModel.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
// libraries
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/*//////////////////////////////////////////////////////////////
                        SuperPoolLens
//////////////////////////////////////////////////////////////*/

contract SuperPoolLens {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                             Data Structs
    //////////////////////////////////////////////////////////////*/

    struct SuperPoolData {
        string name;
        address asset;
        uint256 idleAssets;
        uint256 totalAssets;
        uint256 valueInEth;
        uint256 interestRate;
        PoolDepositData[] deposits;
    }

    struct PoolDepositData {
        address asset;
        uint256 poolId;
        uint256 amount;
        uint256 valueInEth;
        uint256 interestRate;
    }

    struct UserDepositData {
        address owner;
        uint256 interestRate;
        uint256 totalValueInEth;
        SuperPoolDepositData[] deposits;
    }

    struct SuperPoolDepositData {
        address owner;
        address asset;
        address superPool;
        uint256 amount;
        uint256 valueInEth;
        uint256 interestRate;
    }

    Pool public immutable POOL;
    RiskEngine public immutable RISK_ENGINE;

    constructor(address pool_, address riskEngine_) {
        POOL = Pool(pool_);
        RISK_ENGINE = RiskEngine(riskEngine_);
    }

    /*//////////////////////////////////////////////////////////////
                            SuperPool View
    //////////////////////////////////////////////////////////////*/

    function getSuperPoolData(address _superPool) external view returns (SuperPoolData memory) {
        SuperPool superPool = SuperPool(_superPool);
        uint256[] memory pools = superPool.pools();

        PoolDepositData[] memory deposits = new PoolDepositData[](pools.length);
        for (uint256 i; i < pools.length; ++i) {
            deposits[i] = getPoolDepositData(_superPool, pools[i]);
        }

        address asset = address(superPool.asset());
        uint256 totalAssets = superPool.totalAssets();

        return SuperPoolData({
            asset: asset,
            deposits: deposits,
            name: superPool.name(),
            totalAssets: totalAssets,
            valueInEth: _getValueInEth(asset, totalAssets),
            idleAssets: IERC20(asset).balanceOf(_superPool),
            interestRate: getSuperPoolInterestRate(_superPool)
        });
    }

    function getPoolDepositData(address superPool, uint256 _poolId) public view returns (PoolDepositData memory) {
        address asset = POOL.getPoolAssetFor(_poolId);
        uint256 amount = POOL.getAssetsOf(_poolId, superPool);

        return PoolDepositData({
            asset: asset,
            amount: amount,
            poolId: _poolId,
            valueInEth: _getValueInEth(asset, amount),
            interestRate: getPoolInterestRate(_poolId)
        });
    }

    /*//////////////////////////////////////////////////////////////
                              User View
    //////////////////////////////////////////////////////////////*/

    function getUserDepositData(address user, address[] calldata superPools) public view returns (UserDepositData memory) {
        SuperPoolDepositData[] memory deposits = new SuperPoolDepositData[](superPools.length);

        uint256 totalValueInEth;
        uint256 weightedDeposit;

        for (uint256 i; i < superPools.length; ++i) {
            deposits[i] = getSuperPoolDepositData(user, superPools[i]);

            totalValueInEth += deposits[i].valueInEth;

            // [ROUND] deposit weights are rounded up, in favor of the user
            weightedDeposit += (deposits[i].valueInEth).mulDiv(deposits[i].interestRate, 1e18, Math.Rounding.Ceil);
        }

        // [ROUND] interestRate is rounded up, in favor of the user
        uint256 interestRate = (totalValueInEth != 0) ? weightedDeposit.mulDiv(1e18, totalValueInEth, Math.Rounding.Ceil) : 0;

        return UserDepositData({ owner: user, deposits: deposits, totalValueInEth: totalValueInEth, interestRate: interestRate });
    }

    function getSuperPoolDepositData(address user, address _superPool) public view returns (SuperPoolDepositData memory) {
        SuperPool superPool = SuperPool(_superPool);
        address asset = address(superPool.asset());
        uint256 amount = superPool.previewRedeem(superPool.balanceOf(user));

        return SuperPoolDepositData({
            owner: user,
            asset: asset,
            amount: amount,
            superPool: _superPool,
            valueInEth: _getValueInEth(asset, amount),
            interestRate: getSuperPoolInterestRate(_superPool)
        });
    }

    /*//////////////////////////////////////////////////////////////
                         Interest Rates View
    //////////////////////////////////////////////////////////////*/

    function getPoolInterestRate(uint256 _poolId) public view returns (uint256) {
        uint256 borrows = POOL.getTotalBorrows(_poolId);
        uint256 idleAmt; // TODO
        IRateModel irm = IRateModel(POOL.getRateModelFor(_poolId));

        return irm.getInterestRate(borrows, idleAmt);
    }

    function getSuperPoolInterestRate(address _superPool) public view returns (uint256) {
        SuperPool superPool = SuperPool(_superPool);
        uint256 totalAssets = superPool.totalAssets();

        if (totalAssets == 0) return 0;

        uint256 weightedAssets;
        uint256[] memory pools = superPool.pools();
        for (uint256 i; i < pools.length; ++i) {
            uint256 assets = POOL.getAssetsOf(pools[i], _superPool);
            weightedAssets += assets * getPoolInterestRate(pools[i]);
        }

        return weightedAssets / totalAssets;
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
