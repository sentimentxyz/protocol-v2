// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "../BaseScript.s.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { Pool } from "src/Pool.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { RiskModule } from "src/RiskModule.sol";
import { SuperPool } from "src/SuperPool.sol";
import { Position } from "src/Position.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { IRateModel } from "src/interfaces/IRateModel.sol";

interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @dev to run script:
/// forge script RiskView --sig "getSuperPoolData(address)" {SuperPool address} --rpc-url \
/// https://rpc.hyperliquid.xyz/evm
/// forge script RiskView --sig "getPositionData(address)" {Position address} --rpc-url \
/// https://rpc.hyperliquid.xyz/evm
contract RiskView is BaseScript, Test {
    using Math for uint256;

    // pool
    Pool public pool;

    // superPool
    SuperPool public superPool;

    // Risk Engine
    RiskEngine public riskEngine;

    // Risk Module
    RiskModule public riskModule;

    // Position
    Position public position;

    address public constant ethUsdFeed = 0x1b27A24642B1a5a3c54452DDc02F278fb6F63229;

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
        uint256 borrowInterestRate;
        uint256 supplyInterestRate;
    }

    function run() public { }

    function getSuperPoolData(address superPool_) public {
        superPool = SuperPool(superPool_);
        pool = superPool.POOL();
        riskEngine = RiskEngine(pool.riskEngine());

        uint256[] memory pools = superPool.pools(); // fetch underlying pools for given super pool

        // fetch data for each underlying pool
        uint256 poolsLength = pools.length;
        PoolDepositData[] memory deposits = new PoolDepositData[](poolsLength);
        uint256[] memory withdrawQueue = new uint256[](pools.length);
        for (uint256 i; i < poolsLength; ++i) {
            deposits[i] = getPoolDepositData(superPool_, pools[i]);
            withdrawQueue[i] = superPool.withdrawQueue(i);
        }

        // aggregate data from underlying pools
        address asset = address(superPool.asset());
        uint256 totalAssets = superPool.totalAssets();

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
            idleAssetsUsd: ethToUsd(_getValueInEth(asset, IERC20(asset).balanceOf(superPool_)) / 1e18),
            totalAssets: totalAssets,
            totalAssetsUsd: ethToUsd(_getValueInEth(asset, totalAssets) / 1e18),
            supplyRate: getSuperPoolInterestRate(superPool_),
            superPoolCap: superPool.superPoolCap(),
            depositQueue: superPool.pools(),
            withdrawQueue: withdrawQueue,
            poolDepositData: deposits
        });

        console2.log("superPool address: ", superPoolData.pool);
        console2.log("decimals: ", superPoolData.decimals);
        console2.log("name: ", superPoolData.name);
        console2.log("isPaused: ", superPoolData.isPaused);
        console2.log("asset: ", superPoolData.asset);
        console2.log("owner: ", superPoolData.owner);
        console2.log("feeRecipient: ", superPoolData.feeRecipient);
        console2.log("fee: ", superPoolData.fee, "USD");
        console2.log("idleAssets: ", superPoolData.idleAssets / 1e18, IERC20(superPoolData.asset).symbol());
        console2.log("idleAssetsUsd: ", superPoolData.idleAssetsUsd, "USD");
        console2.log("totalAssets: ", superPoolData.totalAssets / 1e18, IERC20(superPoolData.asset).symbol());
        console2.log("totalAssetsUsd: ", superPoolData.totalAssetsUsd, "USD");
        console2.log("supplyRate: %4e%", superPoolData.supplyRate / 1e12);
        console2.log("superPoolCap: ", superPoolData.superPoolCap / 1e18, IERC20(superPoolData.asset).symbol());
        console2.log("superPool utilization rate: %2e%", getSuperPoolUtilizationRate() / 1e14);
        console2.log("");
        console2.log("depositQueue: ");
        emit log_array(superPoolData.depositQueue);
        console2.log("");
        console2.log("withdrawQueue: ");
        emit log_array(superPoolData.withdrawQueue);
        console2.log("");
        console2.log("poolDepositData: ");
        for (uint256 i = 0; i < poolsLength; ++i) {
            console2.log("pool #: ", i + 1);
            console2.log("asset: ", deposits[i].asset);
            console2.log("poolId: ", deposits[i].poolId);
            console2.log("amount of assets: ", deposits[i].amount / 1e18, IERC20(superPoolData.asset).symbol());
            console2.log("rateModel: ", pool.getRateModelFor(deposits[i].poolId));
            console2.log("valueInEth: ", deposits[i].valueInEth / 1e18, "ETH");
            console2.log("valueInUsd: ", ethToUsd(deposits[i].valueInEth) / 1e18, "USD");
            console2.log("borrowRate: %4e%", deposits[i].borrowInterestRate / 1e12);
            console2.log("supplyRate: %4e%", deposits[i].supplyInterestRate / 1e12);
            console2.log(
                "totalBorrows: ", pool.getTotalBorrows(deposits[i].poolId) / 1e18, IERC20(superPoolData.asset).symbol()
            );
            console2.log(
                "pool borrow cap: ",
                pool.getBorrowCapFor(deposits[i].poolId) / 1e18,
                IERC20(superPoolData.asset).symbol()
            );
            console2.log(
                "total supplied: ", pool.getTotalAssets(deposits[i].poolId) / 1e18, IERC20(superPoolData.asset).symbol()
            );
            console2.log(
                "pool supply cap: ", pool.getPoolCapFor(deposits[i].poolId) / 1e18, IERC20(superPoolData.asset).symbol()
            );
            console2.log("pool utilization rate: %2e%", getPoolUtilizationRate(deposits[i].poolId) / 1e14);
        }
        console2.log("");
        console2.log("oracles:");
        console2.log("borrowAsset: ", superPoolData.asset);
        console2.log("oracle addr: ", riskEngine.oracleFor(superPoolData.asset));
        console2.log("oracle eth price: %18e", _getValueInEth(superPoolData.asset, 1e18), "ETH");
        console2.log("oracle usd price: %2e", ethToUsd(_getValueInEth(superPoolData.asset, 1e18)) / 1e16, "USD");

        address collateralAsset = 0x94e8396e0869c9F2200760aF0621aFd240E1CF38; // wstHype
        console2.log("collateralAsset: ", collateralAsset);
        console2.log("oracle addr: ", riskEngine.oracleFor(collateralAsset));
        console2.log("oracle eth price: %18e", _getValueInEth(collateralAsset, 1e18), "ETH");
        console2.log("oracle usd price: %2e", ethToUsd(_getValueInEth(collateralAsset, 1e18)) / 1e16, "USD");
    }

    function getPositionData(address position_) public {
        position = Position(payable(position_));
        pool = Pool(position.POOL());
        riskEngine = RiskEngine(position.RISK_ENGINE());
        riskModule = RiskModule(riskEngine.riskModule());
        console2.log("riskEngine", address(riskEngine));
        console2.log("riskModule", address(riskModule));

        console2.log("Position:");
        console2.log("debtPools: ");
        emit log_array(position.getDebtPools());
        console2.log("positionAssets: ");
        emit log_array(position.getPositionAssets());
        //console2.log("debtAsset: ", pool.getPoolAssetFor());

        (uint256 totalAssetValue, uint256 totalDebtValue, uint256 weightedLtv)= riskEngine.getRiskData(position_);
        console2.log("getRiskData:");
        console2.log("totalAssetValue: ");
        console2.log("%4e ETH, %2e USD", totalAssetValue / 1e14, ethToUsd(totalAssetValue) / 1e16);
        console2.log("totalDebtValue: ");
        console2.log("%4e ETH, %2e USD", totalDebtValue / 1e14, ethToUsd(totalDebtValue) / 1e16);
        console2.log("weightedLtv: ");
        console2.log("%4e", weightedLtv / 1e14);
        console2.log("position healthFactor: %4e", riskModule.getPositionHealthFactor(position_) / 1e14);
    }

    function getPoolDepositData(
        address superPool_,
        uint256 poolId
    )
        public
        view
        returns (PoolDepositData memory poolDepositData)
    {
        address asset = pool.getPoolAssetFor(poolId);
        uint256 amount = pool.getAssetsOf(poolId, superPool_);

        return PoolDepositData({
            asset: asset,
            amount: amount,
            poolId: poolId,
            valueInEth: _getValueInEth(asset, amount),
            borrowInterestRate: getPoolBorrowRate(poolId),
            supplyInterestRate: getPoolSupplyRate(poolId)
        });
    }

    function getPoolUtilizationRate(uint256 poolId) public view returns (uint256 utilizationRate) {
        uint256 totalBorrows = pool.getTotalBorrows(poolId);
        uint256 totalAssets = pool.getTotalAssets(poolId);
        utilizationRate = totalAssets == 0 ? 0 : totalBorrows.mulDiv(1e18, totalAssets, Math.Rounding.Up);
    }

    function getSuperPoolUtilizationRate() public view returns (uint256 utilizationRate) {
        uint256 totalAssets = superPool.totalAssets();

        if (totalAssets == 0) return 0;
        uint256 totalBorrows;

        uint256[] memory pools = superPool.pools();
        uint256 poolsLength = pools.length;
        for (uint256 i; i < poolsLength; ++i) {
            totalBorrows += pool.getTotalBorrows(pools[i]);
        }

        utilizationRate = totalBorrows == 0 ? 0 : totalBorrows.mulDiv(1e18, totalAssets, Math.Rounding.Up);
    }

    function _getValueInEth(address asset, uint256 amt) internal view returns (uint256) {
        IOracle oracle = IOracle(riskEngine.oracleFor(asset));

        // oracles could revert, but lens calls must not
        try oracle.getValueInEth(asset, amt) returns (uint256 valueInEth) {
            return valueInEth;
        } catch {
            return 0;
        }
    }

    function getSuperPoolInterestRate(address _superPool) public view returns (uint256 weightedInterestRate) {
        uint256 totalAssets = superPool.totalAssets();

        if (totalAssets == 0) return 0;

        uint256[] memory pools = superPool.pools();
        uint256 poolsLength = pools.length;
        for (uint256 i; i < poolsLength; ++i) {
            uint256 assets = pool.getAssetsOf(pools[i], _superPool);
            uint256 utilization = assets.mulDiv(1e18, totalAssets);
            weightedInterestRate += utilization.mulDiv(getPoolSupplyRate(pools[i]), 1e18);
        }
    }

    function getPoolBorrowRate(uint256 poolId) public view returns (uint256 interestRate) {
        IRateModel irm = IRateModel(pool.getRateModelFor(poolId));
        return irm.getInterestRate(pool.getTotalBorrows(poolId), pool.getTotalAssets(poolId));
    }

    function getPoolSupplyRate(uint256 poolId) public view returns (uint256 interestRate) {
        uint256 borrowRate = getPoolBorrowRate(poolId);
        uint256 util = getPoolUtilizationRate(poolId);
        return borrowRate.mulDiv(util, 1e18);
    }

    function ethToUsd(uint256 amt) public view returns (uint256 usd) {
        (, int256 answer,,,) = IAggregatorV3(ethUsdFeed).latestRoundData();
        usd = amt.mulDiv(uint256(answer), 1e8);
    }
}
