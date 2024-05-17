// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import {Pool} from "../Pool.sol";
import {SuperPool} from "../SuperPool.sol";
import {IRateModel} from "../interfaces/IRateModel.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
// libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

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
        uint256 interestRate;
        PoolDepositData[] deposits;
    }

    struct PoolDepositData {
        uint256 poolId;
        address asset;
        uint256 amount;
        uint256 interestRate;
    }

    struct UserDepositData {
        uint256 interestRate;
        uint256 totalDeposits;
        SuperPoolDepositData[] deposits;
    }

    struct SuperPoolDepositData {
        address superPool;
        address asset;
        uint256 amount;
        uint256 interestRate;
    }

    Pool public immutable POOL;

    constructor(address pool_) {
        POOL = Pool(pool_);
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

        return SuperPoolData({
            asset: asset,
            deposits: deposits,
            name: superPool.name(),
            totalAssets: superPool.totalAssets(),
            idleAssets: IERC20(asset).balanceOf(_superPool),
            interestRate: getSuperPoolInterestRate(_superPool)
        });
    }

    function getPoolDepositData(address superPool, uint256 _poolId) public view returns (PoolDepositData memory) {
        address asset = POOL.getPoolAssetFor(_poolId);

        return PoolDepositData({
            poolId: _poolId,
            asset: asset,
            interestRate: getPoolInterestRate(_poolId),
            amount: POOL.getAssetsOf(_poolId, superPool)
        });
    }

    /*//////////////////////////////////////////////////////////////
                              User View
    //////////////////////////////////////////////////////////////*/

    function getUserDepositData(address user, address[] calldata superPools)
        public
        view
        returns (UserDepositData memory)
    {
        SuperPoolDepositData[] memory deposits = new SuperPoolDepositData[](superPools.length);

        uint256 totalDeposits;
        uint256 weightedDeposit;

        for (uint256 i; i < superPools.length; ++i) {
            deposits[i] = getSuperPoolDepositData(user, superPools[i]);

            totalDeposits += deposits[i].amount;

            // [ROUND] deposit weights are rounded up, in favor of the user
            weightedDeposit += (deposits[i].amount).mulDiv(deposits[i].interestRate, 1e18, Math.Rounding.Ceil);
        }
        return UserDepositData({
            deposits: deposits,
            totalDeposits: totalDeposits,
            // [ROUND] interestRate is rounded up, in favor of the user
            interestRate: weightedDeposit.mulDiv(1e18, totalDeposits, Math.Rounding.Ceil)
        });
    }

    function getSuperPoolDepositData(address user, address _superPool)
        public
        view
        returns (SuperPoolDepositData memory)
    {
        SuperPool superPool = SuperPool(_superPool);
        address asset = address(superPool.asset());

        return SuperPoolDepositData({
            superPool: _superPool,
            asset: asset,
            interestRate: getSuperPoolInterestRate(_superPool),
            amount: superPool.previewRedeem(IERC20(asset).balanceOf(user))
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
}
