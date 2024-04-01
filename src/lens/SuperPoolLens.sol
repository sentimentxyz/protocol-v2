// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import {Pool} from "../Pool.sol";
import {SuperPool} from "../SuperPool.sol";
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
        address pool;
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

    /*//////////////////////////////////////////////////////////////
                            SuperPool View
    //////////////////////////////////////////////////////////////*/

    function getSuperPoolData(address _superPool) external view returns (SuperPoolData memory) {
        SuperPool superPool = SuperPool(_superPool);
        address[] memory pools = superPool.pools();

        PoolDepositData[] memory deposits = new PoolDepositData[](pools.length);
        for (uint256 i; i < pools.length; ++i) {
            deposits[i] = getPoolDepositData(_superPool, pools[i]);
        }

        address asset = superPool.asset();

        return SuperPoolData({
            asset: asset,
            deposits: deposits,
            name: superPool.name(),
            totalAssets: superPool.totalAssets(),
            idleAssets: IERC20(asset).balanceOf(_superPool),
            interestRate: getSuperPoolInterestRate(_superPool)
        });
    }

    function getPoolDepositData(address superPool, address _pool) public view returns (PoolDepositData memory) {
        Pool pool = Pool(_pool);
        address asset = pool.asset();

        return PoolDepositData({
            pool: _pool,
            asset: asset,
            interestRate: getPoolInterestRate(_pool),
            amount: IERC4626(_pool).previewRedeem(IERC20(asset).balanceOf(superPool))
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
        address asset = superPool.asset();

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

    function getPoolInterestRate(address _pool) public view returns (uint256) {
        Pool pool = Pool(_pool);
        uint256 borrows = pool.getTotalBorrows();
        uint256 idleAmt = IERC20(pool.asset()).balanceOf(_pool);

        return pool.rateModel().getInterestRate(borrows, idleAmt);
    }

    function getSuperPoolInterestRate(address _superPool) public view returns (uint256) {
        SuperPool superPool = SuperPool(_superPool);
        address asset = superPool.asset();
        uint256 totalAssets = superPool.totalAssets();

        if (totalAssets == 0) return 0;

        uint256 weightedAssets;
        address[] memory pools = superPool.pools();
        for (uint256 i; i < pools.length; ++i) {
            uint256 assets = IERC4626(pools[i]).previewRedeem(IERC20(asset).balanceOf(_superPool));
            weightedAssets += assets * getPoolInterestRate(pools[i]);
        }

        return weightedAssets / totalAssets;
    }
}
