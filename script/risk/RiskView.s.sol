// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "../BaseScript.s.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { Pool } from "src/Pool.sol";

import { RiskEngine } from "src/RiskEngine.sol";
import { SuperPool } from "src/SuperPool.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { IRateModel } from "src/interfaces/IRateModel.sol";
import { SuperPoolLens } from "src/lens/SuperPoolLens.sol";

/// @dev to run script:
/// forge script RiskView --sig "getSuperPoolData(address)" {SuperPool address} --rpc-url \
/// https://rpc.hyperliquid.xyz/evm
contract RiskView is BaseScript, Test {
    // pool
    address poolImpl;
    Pool public POOL;

    // superPool
    SuperPool public superPool;

    // lens
    SuperPoolLens public superPoolLens;

    // Risk Engine
    RiskEngine public RISK_ENGINE;

    struct SuperPoolData {
        address pool;
        uint8 decimals;
        string name;
        bool isPaused;
        address asset;
        address owner;
        address feeRecipient;
        uint256 fee;
        uint256 idleAssets;
        uint256 idleAssetsUsd;
        uint256 totalAssets;
        uint256 totalAssetsUsd;
        uint256 supplyRate;
        uint256 superPoolCap;
        uint256[] depositQueue;
        uint256[] withdrawQueue;
        PoolDepositData[] poolDepositData;
    }

    struct PoolDepositData {
        address asset;
        uint256 poolId;
        uint256 amount; // amount of assets deposited from the super pool into this pool
        uint256 valueInEth;
        uint256 interestRate;
    }

    struct BasePoolData {
        uint256 util;
        address asset;
        uint256 poolId;
        uint256 shares;
        uint256 amount;
        uint256 amountUsd;
        uint256 supplyRate;
        uint256 borrowRate;
        uint256 poolCapFor;
    }

    function run() public { }

    function getSuperPoolData(address superPool_) public {
        superPool = SuperPool(superPool_);
        POOL = superPool.POOL();
        RISK_ENGINE = RiskEngine(POOL.riskEngine());

        uint256[] memory pools = superPool.pools(); // fetch underlying pools for given super pool

        // fetch data for each underlying pool
        uint256 poolsLength = pools.length;
        PoolDepositData[] memory deposits = new PoolDepositData[](poolsLength);
        for (uint256 i; i < poolsLength; ++i) {
            deposits[i] = getPoolDepositData(superPool_, pools[i]);
        }

        // aggregate data from underlying pools
        address asset = address(superPool.asset());
        uint256 totalAssets = superPool.totalAssets();

        // get withdraw queue
        uint256[] memory withdrawQueue = new uint256[](1);
        //uint256[] memory withdrawQueue = new uint256[](superPool.withdrawQueue().length());

        SuperPoolData memory superPoolData = SuperPoolData({
            decimals: superPool.decimals(),
            pool: superPool_,
            name: superPool.name(),
            isPaused: superPool.paused(),
            asset: asset,
            owner: superPool.owner(),
            feeRecipient: superPool.feeRecipient(),
            fee: superPool.fee(),
            idleAssets: IERC20(asset).balanceOf(superPool_),
            idleAssetsUsd: ethToUsd(IERC20(asset).balanceOf(superPool_)),
            totalAssets: totalAssets,
            totalAssetsUsd: ethToUsd(totalAssets),
            supplyRate: getSuperPoolInterestRate(superPool_),
            superPoolCap: superPool.superPoolCap(),
            depositQueue: superPool.pools(),
            withdrawQueue: withdrawQueue, //superPool.withdrawQueue(),
            poolDepositData: deposits
        });
        console2.log("superPool address: ", superPoolData.pool);
        console2.log("decimals: ", superPoolData.decimals);
        console2.log("name: ", superPoolData.name);
        console2.log("isPaused: ", superPoolData.isPaused);
        console2.log("asset: ", superPoolData.asset);
        console2.log("owner: ", superPoolData.owner);
        console2.log("feeRecipient: ", superPoolData.feeRecipient);
        console2.log("fee: ", superPoolData.fee);
        console2.log("idleAssets: ", superPoolData.idleAssets);
        console2.log("idleAssetsUsd: ", superPoolData.idleAssetsUsd);
        console2.log("totalAssets: ", superPoolData.totalAssets);
        console2.log("totalAssetsUsd: ", superPoolData.totalAssets);
        console2.log("supplyRate: ", superPoolData.supplyRate);
        console2.log("superPoolCap: ", superPoolData.superPoolCap);
        console2.log("depositQueue: ");
        emit log_array(superPoolData.depositQueue);
        console2.log("withdrawQueue: ");
        emit log_array(superPoolData.withdrawQueue);
        console2.log("poolDepositData: ");
        //emit log_array(superPoolData.deposits);
    }

    function getPoolDepositData(
        address superPool_,
        uint256 poolId
    )
        public
        view
        returns (PoolDepositData memory poolDepositData)
    {
        address asset = POOL.getPoolAssetFor(poolId);
        uint256 amount = POOL.getAssetsOf(poolId, superPool_);

        return PoolDepositData({
            asset: asset,
            amount: amount,
            poolId: poolId,
            valueInEth: _getValueInEth(asset, amount),
            interestRate: getPoolInterestRate(poolId)
        });
    }

    function _getValueInEth(address asset, uint256 amt) internal view returns (uint256) {
        IOracle oracle = IOracle(RISK_ENGINE.oracleFor(asset));

        // oracles could revert, but lens calls must not
        try oracle.getValueInEth(asset, amt) returns (uint256 valueInEth) {
            return valueInEth;
        } catch {
            return 0;
        }
    }

    function getSuperPoolInterestRate(address _superPool) public view returns (uint256 interestRate) {
        uint256 totalAssets = superPool.totalAssets();

        if (totalAssets == 0) return 0;

        uint256 weightedAssets;
        uint256[] memory pools = superPool.pools();
        uint256 poolsLength = pools.length;
        for (uint256 i; i < poolsLength; ++i) {
            uint256 assets = POOL.getAssetsOf(pools[i], _superPool);
            weightedAssets += assets * getPoolInterestRate(pools[i]);
        }

        return weightedAssets / totalAssets;
    }

    function getPoolInterestRate(uint256 poolId) public view returns (uint256 interestRate) {
        IRateModel irm = IRateModel(POOL.getRateModelFor(poolId));
        return irm.getInterestRate(POOL.getTotalBorrows(poolId), POOL.getTotalAssets(poolId));
    }

    function ethToUsd(uint256 amt) public pure returns (uint256 price) {
        amt;
        price;
    }
}
