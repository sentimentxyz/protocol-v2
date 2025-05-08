// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { BaseSentimentInvariant } from "../invariants/BaseSentimentInvariant.t.sol";

import { Pool } from "src/Pool.sol";
import { SuperPool } from "src/SuperPool.sol";
import { MockSuperPool } from "test/mocks/MockSuperPool.sol";

import { Action, AssetData, DebtData, Operation, PositionManager } from "src/PositionManager.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract BeforeAfter is BaseSentimentInvariant {
    using Math for uint256;

    struct Vars {
        Pool.PoolData poolData;
        uint256 fromAssetBalance;
        uint256 fromShareBalance;
        uint256 receiverAssetBalance;
        uint256 receiverShareBalance;
        uint256 feeRecipientAssetBalance;
        uint256 feeRecipientShareBalance;
        uint256 poolAssetBalance;
    }

    function __before(uint256 poolId, address from, address receiver) internal view returns (Vars memory _before) {
        Pool.PoolData memory _poolData = pool.getPoolData(poolId);
        _before.poolData = _poolData;
        _before.fromAssetBalance = IERC20(_poolData.asset).balanceOf(from);
        _before.fromShareBalance = pool.balanceOf(from, poolId);
        _before.receiverAssetBalance = IERC20(_poolData.asset).balanceOf(receiver);
        _before.receiverShareBalance = pool.balanceOf(receiver, poolId);
        _before.feeRecipientAssetBalance = IERC20(_poolData.asset).balanceOf(pool.feeRecipient());
        _before.feeRecipientShareBalance = pool.balanceOf(pool.feeRecipient(), poolId);
        _before.poolAssetBalance = IERC20(_poolData.asset).balanceOf(address(pool));
    }

    function __after(uint256 poolId, address from, address receiver) internal view returns (Vars memory _after) {
        Pool.PoolData memory _poolData = pool.getPoolData(poolId);
        _after.poolData = _poolData;
        _after.fromAssetBalance = IERC20(_poolData.asset).balanceOf(from);
        _after.fromShareBalance = pool.balanceOf(from, poolId);
        _after.receiverAssetBalance = IERC20(_poolData.asset).balanceOf(receiver);
        _after.receiverShareBalance = pool.balanceOf(receiver, poolId);
        _after.feeRecipientAssetBalance = IERC20(_poolData.asset).balanceOf(pool.feeRecipient());
        _after.feeRecipientShareBalance = pool.balanceOf(pool.feeRecipient(), poolId);
        _after.poolAssetBalance = IERC20(_poolData.asset).balanceOf(address(pool));
    }

    struct PositionManagerVars {
        bool isAuth;
        address ownerOf;
        uint256 fromAssetBalance;
        uint256 recipientAssetBalance;
        uint256 positionAssetBalance;
        uint256 positionAssetValue;
        uint256 positionDebtValue;
        uint256 positionBorrowShares;
        uint256 minReqValue;
    }

    function __beforePM(
        address from,
        address recipient,
        address position,
        address asset,
        uint256 poolId
    ) internal view returns (PositionManagerVars memory _before) {
        _before.isAuth = positionManager.isAuth(position, from);
        _before.ownerOf = positionManager.ownerOf(position);
        _before.fromAssetBalance = IERC20(asset).balanceOf(from);
        _before.recipientAssetBalance = IERC20(asset).balanceOf(recipient);
        _before.positionAssetBalance = IERC20(asset).balanceOf(position);
        _before.positionBorrowShares = pool.borrowSharesOf(poolId, position);
        (_before.positionAssetValue, _before.positionDebtValue, _before.minReqValue) = riskModule.getRiskData(position);
    }

    function __afterPM(
        address from,
        address recipient,
        address position,
        address asset,
        uint256 poolId
    ) internal view returns (PositionManagerVars memory _after) {
        _after.isAuth = positionManager.isAuth(position, from);
        _after.ownerOf = positionManager.ownerOf(position);
        _after.fromAssetBalance = IERC20(asset).balanceOf(from);
        _after.recipientAssetBalance = IERC20(asset).balanceOf(recipient);
        _after.positionAssetBalance = IERC20(asset).balanceOf(position);
        _after.positionBorrowShares = pool.borrowSharesOf(poolId, position);
    }

    struct LiquidationVars {
        uint256 totalDebtAsset1;
        uint256 totalDebtAsset2;
        uint256 totalPositionAsset1;
        uint256 totalPositionAsset2;
        uint256 poolAsset1Balance;
        uint256 poolAsset2Balance;
        uint256 liquidatorAsset1Balance;
        uint256 liquidatorAsset2Balance;
        uint256 positionAsset1Balance;
        uint256 positionAsset2Balance;
        uint256 ownerAsset1Balance;
        uint256 ownerAsset2Balance;
        uint256 asset1LiquidationFee;
        uint256 asset2LiquidationFee;
        Pool.PoolData[] poolData;
        uint256[] positionBorrowShares;
    }

    function __beforeLiq(
        DebtData[] memory debt,
        AssetData[] memory assets,
        address liquidator,
        address position
    ) internal returns (LiquidationVars memory _before) {
        _before.poolAsset1Balance = IERC20(address(asset1)).balanceOf(address(pool));
        _before.poolAsset2Balance = IERC20(address(asset2)).balanceOf(address(pool));
        _before.liquidatorAsset1Balance = IERC20(address(asset1)).balanceOf(liquidator);
        _before.liquidatorAsset2Balance = IERC20(address(asset2)).balanceOf(liquidator);
        _before.positionAsset1Balance = IERC20(address(asset1)).balanceOf(position);
        _before.positionAsset2Balance = IERC20(address(asset2)).balanceOf(position);
        _before.ownerAsset1Balance = IERC20(address(asset1)).balanceOf(positionManager.owner());
        _before.ownerAsset2Balance = IERC20(address(asset2)).balanceOf(positionManager.owner());

        _before.poolData = new Pool.PoolData[](debt.length);
        _before.positionBorrowShares = new uint256[](debt.length);

        for (uint256 i = 0; i < debt.length; i++) {
            address poolAsset = pool.getPoolAssetFor(debt[i].poolId);

            if (poolAsset == address(asset1)) _before.totalDebtAsset1 += debt[i].amt;
            else _before.totalDebtAsset2 += debt[i].amt;
            pool.accrue(debt[i].poolId);
            _before.poolData[i] = pool.getPoolData(debt[i].poolId);
            _before.positionBorrowShares[i] = pool.borrowSharesOf(debt[i].poolId, position);
        }

        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].asset == address(asset1)) {
                _before.asset1LiquidationFee += (positionManager.liquidationFee()).mulDiv(assets[i].amt, 1e18);
                _before.totalPositionAsset1 += assets[i].amt;
            } else {
                _before.asset2LiquidationFee += (positionManager.liquidationFee()).mulDiv(assets[i].amt, 1e18);
                _before.totalPositionAsset2 += assets[i].amt;
            }
        }
    }

    function __afterLiq(
        DebtData[] memory debt,
        AssetData[] memory assets,
        address liquidator,
        address position
    ) internal view returns (LiquidationVars memory _after) {
        _after.poolAsset1Balance = IERC20(address(asset1)).balanceOf(address(pool));
        _after.poolAsset2Balance = IERC20(address(asset2)).balanceOf(address(pool));
        _after.liquidatorAsset1Balance = IERC20(address(asset1)).balanceOf(liquidator);
        _after.liquidatorAsset2Balance = IERC20(address(asset2)).balanceOf(liquidator);
        _after.positionAsset1Balance = IERC20(address(asset1)).balanceOf(position);
        _after.positionAsset2Balance = IERC20(address(asset2)).balanceOf(position);
        _after.ownerAsset1Balance = IERC20(address(asset1)).balanceOf(positionManager.owner());
        _after.ownerAsset2Balance = IERC20(address(asset2)).balanceOf(positionManager.owner());

        _after.poolData = new Pool.PoolData[](debt.length);
        _after.positionBorrowShares = new uint256[](debt.length);

        for (uint256 i = 0; i < debt.length; i++) {
            address poolAsset = pool.getPoolAssetFor(debt[i].poolId);

            if (poolAsset == address(asset1)) _after.totalDebtAsset1 += debt[i].amt;
            else _after.totalDebtAsset2 += debt[i].amt;
            _after.poolData[i] = pool.getPoolData(debt[i].poolId);
            _after.positionBorrowShares[i] = pool.borrowSharesOf(debt[i].poolId, position);
        }

        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].asset == address(asset1)) {
                _after.asset1LiquidationFee += (positionManager.liquidationFee()).mulDiv(assets[i].amt, 1e18);
                _after.totalPositionAsset1 += assets[i].amt;
            } else {
                _after.asset2LiquidationFee += (positionManager.liquidationFee()).mulDiv(assets[i].amt, 1e18);
                _after.totalPositionAsset2 += assets[i].amt;
            }
        }
    }

    struct SuperPoolVars {
        uint256 sharesExpectedDeposit;
        uint256 assetsExpectedMint;
        uint256 sharesExpectedWithdraw;
        uint256 assetsExpectedRedeem;
        uint256 shareBalanceFrom;
        uint256 shareBalanceReceiver;
        uint256 assetBalanceFrom;
        uint256 assetBalanceReceiver;
        uint256 lastTotalAssets;
        uint256 superPoolPendingInterest;
        uint256[] assetDeposits;
        uint256[] shareDeposits;
        uint256[] assetWithdraws;
        uint256[] shareWithdraws;
        uint256[] pendingInterest;
        uint256 poolAssetBalance;
        uint256[] superPoolShareBalance;
        Pool.PoolData[] poolData;
    }

    function __beforeSP(
        MockSuperPool superPool,
        address from,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal view returns (SuperPoolVars memory _before) {
        _before.sharesExpectedDeposit = superPool.previewDeposit(assets);
        _before.assetsExpectedMint = superPool.previewMint(shares);
        _before.sharesExpectedWithdraw = superPool.previewWithdraw(assets);
        _before.assetsExpectedRedeem = superPool.previewRedeem(shares);
        _before.shareBalanceFrom = superPool.balanceOf(from);
        _before.shareBalanceReceiver = superPool.balanceOf(receiver);
        _before.assetBalanceFrom = IERC20(superPool.asset()).balanceOf(from);
        _before.assetBalanceReceiver = IERC20(superPool.asset()).balanceOf(receiver);
        _before.lastTotalAssets = superPool.lastTotalAssets();
        (, uint256 newTotalAssets) = superPool.superPoolSimulateAccrue();
        _before.superPoolPendingInterest =
            _before.lastTotalAssets > newTotalAssets ? 0 : newTotalAssets - superPool.lastTotalAssets();

        uint256 poolCount = superPool.getPoolCount();
        _before.poolData = new Pool.PoolData[](poolCount);
        _before.pendingInterest = new uint256[](poolCount);
        _before.superPoolShareBalance = new uint256[](poolCount);
        _before.assetDeposits = new uint256[](poolCount);
        _before.shareDeposits = new uint256[](poolCount);

        _before = _populateDepositData(superPool, from, receiver, assets, _before);

        _before.assetWithdraws = new uint256[](poolCount);
        _before.shareWithdraws = new uint256[](poolCount);
        _before = _populateWithdrawData(superPool, from, receiver, assets, _before);
    }

    function __afterSP(
        MockSuperPool superPool,
        address from,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal view returns (SuperPoolVars memory _after) {
        _after.sharesExpectedDeposit = superPool.previewDeposit(assets);
        _after.assetsExpectedMint = superPool.previewMint(shares);
        _after.sharesExpectedWithdraw = superPool.previewWithdraw(assets);
        _after.assetsExpectedRedeem = superPool.previewRedeem(shares);
        _after.shareBalanceFrom = superPool.balanceOf(from);
        _after.shareBalanceReceiver = superPool.balanceOf(receiver);
        _after.assetBalanceFrom = IERC20(superPool.asset()).balanceOf(from);
        _after.assetBalanceReceiver = IERC20(superPool.asset()).balanceOf(receiver);
        _after.lastTotalAssets = superPool.lastTotalAssets();

        uint256 poolCount = superPool.getPoolCount();
        _after.poolData = new Pool.PoolData[](poolCount);
        _after.pendingInterest = new uint256[](poolCount);
        _after.superPoolShareBalance = new uint256[](poolCount);
        _after.assetDeposits = new uint256[](poolCount);
        _after.shareDeposits = new uint256[](poolCount);

        _after = _populateDepositData(superPool, from, receiver, assets, _after);

        _after.assetWithdraws = new uint256[](poolCount);
        _after.shareWithdraws = new uint256[](poolCount);
        _after = _populateWithdrawData(superPool, from, receiver, assets, _after);
    }

    function _populateDepositData(
        MockSuperPool superPool,
        address from,
        address receiver,
        uint256 assets,
        SuperPoolVars memory superPoolVars
    ) internal view returns (SuperPoolVars memory) {
        uint256 _assets = assets;
        Vars memory poolVars;
        for (uint256 i; i < superPool.getPoolCount(); ++i) {
            uint256 poolId = superPool.depositQueue(i);

            poolVars = __after(poolId, from, receiver);
            superPoolVars.poolData[i] = poolVars.poolData;
            uint256 assetsInPool = pool.getAssetsOf(poolId, address(superPool));
            (uint256 pendingInterest, ) = pool.mockSimulateAccrue(poolId);
            superPoolVars.pendingInterest[i] = pendingInterest;
            superPoolVars.poolAssetBalance = IERC20(poolVars.poolData.asset).balanceOf(address(pool));
            superPoolVars.superPoolShareBalance[i] = pool.balanceOf(address(superPool), poolId);

            if (assetsInPool < superPool.poolCapFor(poolId)) {
                uint256 supplyAmt = superPool.poolCapFor(poolId) - assetsInPool;
                if (_assets < supplyAmt) supplyAmt = _assets;
                superPoolVars.assetDeposits[i] = supplyAmt;
                superPoolVars.shareDeposits[i] = pool.convertToSharesRounding(
                    supplyAmt, 
                    poolVars.poolData.totalDepositAssets + pendingInterest, 
                    poolVars.poolData.totalDepositShares,
                    Math.Rounding.Down
                );

                _assets -= supplyAmt;

                if (_assets == 0) break;
            }
        }
        return superPoolVars;
    }

    function _populateWithdrawData(
        MockSuperPool superPool,
        address from,
        address receiver,
        uint256 assets,
        SuperPoolVars memory superPoolVars
    ) internal view returns (SuperPoolVars memory) {
        uint256 assetsInSuperpool = IERC20(superPool.asset()).balanceOf(address(superPool));

        if (assetsInSuperpool >= assets) return superPoolVars;
        else assets -= assetsInSuperpool;

        uint256 _assets = assets;
        Vars memory poolVars;
        for (uint256 i; i < superPool.getPoolCount(); ++i) {
            uint256 poolId = superPool.withdrawQueue(i);

            poolVars = __after(poolId, from, receiver);
            superPoolVars.poolData[i] = poolVars.poolData;
            uint256 assetsInPool = pool.getAssetsOf(poolId, address(superPool));
            (uint256 pendingInterest, ) = pool.mockSimulateAccrue(poolId);
            superPoolVars.pendingInterest[i] = pendingInterest;
            superPoolVars.poolAssetBalance = IERC20(poolVars.poolData.asset).balanceOf(address(pool));
            superPoolVars.superPoolShareBalance[i] = pool.balanceOf(address(superPool), poolId);

            if (assetsInPool > 0) {
                uint256 withdrawAmt = (assetsInPool < _assets) ? assetsInPool : _assets;

                if (withdrawAmt > 0) {
                    superPoolVars.assetWithdraws[i] = withdrawAmt;
                    superPoolVars.shareWithdraws[i] = pool.convertToSharesRounding(
                        _assets, 
                        poolVars.poolData.totalDepositAssets + pendingInterest, 
                        poolVars.poolData.totalDepositShares,
                        Math.Rounding.Down
                    );
                }

                _assets -= withdrawAmt;

                if (_assets == 0) break;
            }
        }
        return superPoolVars;
    }
}
