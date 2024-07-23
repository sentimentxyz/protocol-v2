// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "../helpers/BeforeAfter.sol";
import {Vm} from "forge-std/Test.sol";
import {FuzzLibString} from "@fuzzlib/FuzzLibString.sol";
import {Pool} from "src/Pool.sol";
import {Operation, Action, PositionManager} from "src/PositionManager.sol";
import {SuperPool} from "src/SuperPool.sol";
import {MockSuperPool} from "test/mocks/MockSuperPool.sol";
import {SuperPoolProperties} from "test/invariant/properties/SuperPoolProperties.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract SuperPoolHandler is SuperPoolProperties {
    // forgefmt: disable-start
    /**************************************************************************************************************************/
    /*** Invariant Tests for function deposit                                                                               ***/
    /**************************************************************************************************************************

        * SP-01: SuperPool.deposit() must consume exactly the number of assets requested
        * SP-02: SuperPool.deposit() must credit the correct number of shares to the receiver
        * SP-03: SuperPool.deposit() must credit the correct number of assets to the pools in depositQueue
        * SP-04: SuperPool.deposit() must credit the correct number of shares to the pools in depositQueue
        * SP-05: SuperPool.deposit() must credit the correct number of shares to the SuperPool for the pools in depositQueue
        * SP-06: SuperPool.deposit() must update lastUpdated to the current block.timestamp for the pools in depositQueue
        * SP-07: SuperPool.deposit() must credit pendingInterest to the totalBorrows asset balance for pools in depositQueue
        * SP-08: SuperPool.deposit() must transfer the correct number of assets to the pools in depositQueue
        * SP-09: SuperPool.deposit() must increase the lastTotalAssets by the number of assets provided
        * SP-10: SuperPool.deposit() must always mint greater than or equal to the shares predicted by previewDeposit()

    /**************************************************************************************************************************/
    /*** Assertions that must be true when a user calls deposit                                                             ***/
    /**************************************************************************************************************************/
    // forgefmt: disable-end

    struct SPDepositTemps {
        address owner;
        address receiver;
        address asset;
        uint256 sharesMinted;
        MockSuperPool superPool;
    }

    function superPool_deposit(
        uint256 ownerIndexSeed,
        uint256 receiverIndexSeed,
        uint256 poolIndexSeed,
        uint256 assets
    ) public {
        // PRE-CONDITIONS
        SPDepositTemps memory d;
        d.owner = randomAddress(ownerIndexSeed);
        d.receiver = randomAddress(receiverIndexSeed);
        d.superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        d.asset = d.superPool.asset();

        d.superPool.accrue();

        assets = bound(assets, 0, IERC20(d.asset).balanceOf(d.owner));
        if (assets == 0) return;

        SuperPoolVars memory _beforeSP = __beforeSP(
            d.superPool,
            d.owner,
            d.receiver,
            assets,
            d.superPool.previewDeposit(assets)
        );

        // ACTION
        IERC20 superPoolAsset = IERC20(d.superPool.asset());
        vm.prank(d.owner);
        superPoolAsset.approve(address(d.superPool), assets);

        vm.prank(d.owner);
        try d.superPool.deposit(assets, d.receiver) returns (
            uint256 sharesMinted
        ) {
            d.sharesMinted = sharesMinted;
        } catch (bytes memory err) {
            bytes4[3] memory errors = [
                SuperPool.SuperPool_ZeroShareDeposit.selector,
                Pool.Pool_PoolCapExceeded.selector,
                Pool.Pool_ZeroSharesDeposit.selector
            ];
            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            fl.t(expected, FuzzLibString.getRevertMsg(err));
            return;
        }

        // POST-CONDITIONS
        SuperPoolVars memory _afterSP = __afterSP(
            d.superPool,
            d.owner,
            d.receiver,
            assets,
            d.superPool.previewDeposit(assets)
        );

        fl.eq(
            _afterSP.assetBalanceFrom,
            _beforeSP.assetBalanceFrom - assets,
            "SP-01: SuperPool.deposit() must consume exactly the number of assets requested"
        );
        fl.eq(
            _afterSP.shareBalanceReceiver,
            _beforeSP.shareBalanceReceiver + d.sharesMinted,
            "SP-02: SuperPool.deposit() must credit the correct number of shares to the receiver"
        );

        for (uint256 i = 0; i < _beforeSP.assetDeposits.length; i++) {
            if (_beforeSP.assetDeposits[i] == 0) break;
            
            if (
                _afterSP.poolData[i].totalDepositAssets <
                _beforeSP.poolData[i].totalDepositAssets
            ) {
                fl.eq(
                    _afterSP.poolData[i].totalDepositAssets,
                    _beforeSP.poolData[i].totalDepositAssets +
                        _beforeSP.assetDeposits[i] +
                        _beforeSP.pendingInterest[i],
                    "SP-03: SuperPool.deposit() must credit the correct number of assets to the pools in depositQueue"
                );
                fl.eq(
                    _afterSP.poolData[i].totalDepositShares,
                    _beforeSP.poolData[i].totalDepositShares +
                        _beforeSP.shareDeposits[i],
                    "SP-04: SuperPool.deposit() must credit the correct number of shares to the pools in depositQueue"
                );
                fl.eq(
                    _afterSP.superPoolShareBalance[i],
                    _beforeSP.superPoolShareBalance[i] + _beforeSP.shareDeposits[i],
                    "SP-05: SuperPool.deposit() must credit the correct number of shares to the SuperPool for the pools in depositQueue"
                );
                fl.eq(
                    _afterSP.poolData[i].lastUpdated,
                    uint128(block.timestamp),
                    "SP-06: SuperPool.deposit() must update lastUpdated to the current block.timestamp for the pools in depositQueue"
                );
                if (_beforeSP.pendingInterest[i] > 0) {
                    fl.eq(
                        _afterSP.poolData[i].totalBorrowAssets,
                        _beforeSP.poolData[i].totalBorrowAssets +
                            _beforeSP.pendingInterest[i],
                        "SP-07: SuperPool.deposit() must credit pendingInterest to the totalBorrows asset balance for pools in depositQueue"
                    );
                }
            }
        }
        fl.eq(
            _afterSP.poolAssetBalance,
            _beforeSP.poolAssetBalance + assets,
            "SP-08: SuperPool.deposit() must transfer the correct number of assets to the pools in depositQueue"
        );
        fl.eq(
            _afterSP.lastTotalAssets,
            _beforeSP.lastTotalAssets + assets,
            "SP-09: SuperPool.deposit() must increase the lastTotalAssets by the number of assets provided"
        );
        fl.gte(
            d.sharesMinted,
            _beforeSP.sharesExpectedDeposit,
            "SP-10: SuperPool.deposit() must always mint greater than or equal to the shares predicted by previewDeposit()"
        );
    }

    // forgefmt: disable-start
    /**************************************************************************************************************************/
    /*** Invariant Tests for function mint                                                                                  ***/
    /**************************************************************************************************************************

        * SP-11: SuperPool.mint() must consume exactly the number of tokens requested
        * SP-12: SuperPool.mint() must credit the correct number of shares to the receiver
        * SP-13: SuperPool.mint() must credit the correct number of assets to the pools in depositQueue
        * SP-14: SuperPool.mint() must credit the correct number of shares to the pools in depositQueue
        * SP-15: SuperPool.mint() must credit the correct number of shares to the SuperPool for the pools in depositQueue
        * SP-16: SuperPool.mint() must update lastUpdated to the current block.timestamp for the pools in depositQueue
        * SP-17: SuperPool.mint() must credit pendingInterest to the totalBorrows asset balance for pools in depositQueue
        * SP-18: SuperPool.mint() must transfer the correct number of assets to the base pool for pools in depositQueue
        * SP-19: SuperPool.mint() must increase the lastTotalAssets by the number of assets consumed
        * SP-20: SuperPool.mint() must always consume less than or equal to the tokens predicted by previewMint()

    /**************************************************************************************************************************/
    /*** Assertions that must be true when a user calls mint                                                                ***/
    /**************************************************************************************************************************/
    // forgefmt: disable-end

    struct MintTemps {
        address owner;
        address receiver;
        address asset;
        uint256 assets;
        uint256 assetsConsumed;
        MockSuperPool superPool;
    }

    function superPool_mint(
        uint256 ownerIndexSeed,
        uint256 receiverIndexSeed,
        uint256 poolIndexSeed,
        uint256 shares
    ) public {
        // PRE-CONDITIONS
        MintTemps memory d;
        d.owner = randomAddress(ownerIndexSeed);
        d.receiver = randomAddress(receiverIndexSeed);
        d.superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        d.asset = d.superPool.asset();

        d.superPool.accrue();

        shares = bound(shares, 0, d.superPool.previewDeposit(IERC20(d.asset).balanceOf(d.owner)));
        if (shares == 0) return;

        d.assets = d.superPool.previewMint(shares);
        if (d.assets < IERC20(d.asset).balanceOf(d.owner)) return;

        SuperPoolVars memory _beforeSP = __beforeSP(
            d.superPool,
            d.owner,
            d.receiver,
            d.assets,
            shares
        );

        // ACTION
        IERC20 superPoolAsset = IERC20(d.asset);
        vm.prank(d.owner);
        superPoolAsset.approve(address(d.superPool), d.assets);

        vm.prank(d.owner);
        try d.superPool.mint(shares, d.receiver) returns (
            uint256 assetsConsumed
        ) {
            d.assetsConsumed = assetsConsumed;
        } catch (bytes memory err) {
            bytes4[4] memory errors = [
                SuperPool.SuperPool_ZeroShareDeposit.selector,
                SuperPool.SuperPool_SuperPoolCapReached.selector,
                Pool.Pool_PoolCapExceeded.selector,
                Pool.Pool_ZeroSharesDeposit.selector
            ];
            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            fl.t(expected, FuzzLibString.getRevertMsg(err));
            return;
        }

        // POST-CONDITIONS
        SuperPoolVars memory _afterSP = __afterSP(
            d.superPool,
            d.owner,
            d.receiver,
            d.superPool.previewMint(shares),
            shares
        );

        fl.eq(
            _afterSP.assetBalanceFrom,
            _beforeSP.assetBalanceFrom - d.assetsConsumed,
            "SP-11: SuperPool.mint() must consume exactly the number of tokens requested"
        );
        fl.eq(
            _afterSP.shareBalanceReceiver,
            _beforeSP.shareBalanceReceiver + shares,
            "SP-12: SuperPool.mint() must credit the correct number of shares to the receiver"
        );

        for (uint256 i = 0; i < _beforeSP.assetDeposits.length; i++) {
            if (_beforeSP.assetDeposits[i] == 0) break;

            if (
                _afterSP.poolData[i].totalDepositAssets <
                _beforeSP.poolData[i].totalDepositAssets
            ) {
                fl.eq(
                    _afterSP.poolData[i].totalDepositAssets,
                    _beforeSP.poolData[i].totalDepositAssets +
                        _beforeSP.assetDeposits[i] +
                        _beforeSP.pendingInterest[i],
                    "SP-13: SuperPool.mint() must credit the correct number of assets to the pools in depositQueue"
                );
                fl.eq(
                    _afterSP.poolData[i].totalDepositShares,
                    _beforeSP.poolData[i].totalDepositShares +
                        _beforeSP.shareDeposits[i],
                    "SP-14: SuperPool.mint() must credit the correct number of shares to the pools in depositQueue"
                );
                fl.eq(
                    _afterSP.superPoolShareBalance[i],
                    _beforeSP.superPoolShareBalance[i] + _beforeSP.shareDeposits[i],
                    "SP-15: SuperPool.mint() must credit the correct number of shares to the SuperPool for the pools in depositQueue"
                );
                fl.eq(
                    _afterSP.poolData[i].lastUpdated,
                    uint128(block.timestamp),
                    "SP-16: SuperPool.mint() must update lastUpdated to the current block.timestamp for the pools in depositQueue"
                );
                if (_beforeSP.pendingInterest[i] > 0) {
                    fl.eq(
                        _afterSP.poolData[i].totalBorrowAssets,
                        _beforeSP.poolData[i].totalBorrowAssets +
                            _beforeSP.pendingInterest[i],
                        "SP-17: SuperPool.mint() must credit pendingInterest to the totalBorrows asset balance for pools in depositQueue"
                    );
                }
            }
        }
        fl.eq(
            _afterSP.poolAssetBalance,
            _beforeSP.poolAssetBalance + d.assetsConsumed,
            "SP-18: SuperPool.mint() must transfer the correct number of assets to the base pool for pools in depositQueue"
        );
        fl.eq(
            _afterSP.lastTotalAssets,
            _beforeSP.lastTotalAssets + d.assetsConsumed,
            "SP-19: SuperPool.mint() must increase the lastTotalAssets by the number of assets consumed"
        );
        fl.lte(
            d.assetsConsumed,
            _beforeSP.assetsExpectedMint,
            "SP-20: SuperPool.mint() must always consume less than or equal to the tokens predicted by previewMint()"
        );
    }

    // forgefmt: disable-start
    /*********************************************************************************************************************************************/
    /*** Invariant Tests for function withdraw                                                                                                 ***/
    /*********************************************************************************************************************************************

        * SP-21: SuperPool.withdraw() must credit the correct number of assets to the receiver
        * SP-22: SuperPool.withdraw() must deduct the correct number of shares from the owner
        * SP-23: SuperPool.withdraw() must withdraw the correct number of assets from the pools in withdrawQueue
        * SP-24: SuperPool.withdraw() must withdraw the correct number of shares from the pools in withdrawQueue
        * SP-25: SuperPool.withdraw() must deduct the correct number of shares from the SuperPool share balance for the pools in withdrawQueue
        * SP-26: SuperPool.withdraw() must update lastUpdated to the current block.timestamp for the pools in withdrawQueue
        * SP-27: SuperPool.withdraw() must credit pendingInterest to the totalBorrows asset balance for pools in withdrawQueue
        * SP-28: SuperPool.withdraw() must transfer the correct number of assets from the base pool for pools in withdrawQueue
        * SP-29: SuperPool.withdraw() must decrease the lastTotalAssets by the number of assets consumed
        * SP-30: SuperPool.withdraw() must redeem less than or equal to the number of shares predicted by previewWithdraw()

    /*********************************************************************************************************************************************/
    /*** Assertions that must be true when a user calls withdraw                                                                               ***/
    /*********************************************************************************************************************************************/
    // forgefmt: disable-end

    struct WithdrawTemps {
        address owner;
        address receiver;
        address asset;
        uint256 sharesRedeemed;
        uint256[] withdrawQueue;
        MockSuperPool superPool;
    }

    function superPool_withdraw(
        uint256 ownerIndexSeed,
        uint256 receiverIndexSeed,
        uint256 poolIndexSeed,
        uint256 assets
    ) public {
        // PRE-CONDITIONS
        WithdrawTemps memory d;
        d.owner = randomAddress(ownerIndexSeed);
        d.receiver = randomAddress(receiverIndexSeed);
        d.superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        d.asset = d.superPool.asset();

        d.superPool.accrue();

        assets = bound(assets, 0, d.superPool.maxWithdraw(d.owner));
        if (assets == 0) return;

        SuperPoolVars memory _beforeSP = __beforeSP(
            d.superPool,
            d.owner,
            d.receiver,
            assets,
            d.superPool.previewWithdraw(assets)
        );

        // ACTION
        vm.prank(d.owner);
        try d.superPool.withdraw(assets, d.receiver, d.owner) returns (
            uint256 sharesRedeemed
        ) {
            d.sharesRedeemed = sharesRedeemed;
        } catch (bytes memory err) {
            bytes4[1] memory errors = [
                SuperPool.SuperPool_NotEnoughLiquidity.selector
            ];
            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            fl.t(expected, FuzzLibString.getRevertMsg(err));
            return;
        }

        // POST-CONDITIONS
        SuperPoolVars memory _afterSP = __afterSP(
            d.superPool,
            d.owner,
            d.receiver,
            assets,
            d.superPool.previewWithdraw(assets)
        );

        fl.eq(
            _afterSP.assetBalanceReceiver,
            _beforeSP.assetBalanceReceiver + assets,
            "SP-21: SuperPool.withdraw() must credit the correct number of assets to the receiver"
        );
        fl.eq(
            _afterSP.shareBalanceFrom,
            _beforeSP.shareBalanceFrom - d.sharesRedeemed,
            "SP-22: SuperPool.withdraw() must deduct the correct number of shares from the owner"
        );

        for (uint256 i = 0; i < _beforeSP.assetWithdraws.length; i++) {
            if (_beforeSP.assetWithdraws[i] == 0) break;

            if (
                _afterSP.poolData[i].totalDepositAssets <
                _beforeSP.poolData[i].totalDepositAssets
            ) {
                fl.eq(
                    _afterSP.poolData[i].totalDepositAssets,
                    _beforeSP.poolData[i].totalDepositAssets -
                        _beforeSP.assetWithdraws[i] +
                        _beforeSP.pendingInterest[i],
                    "SP-23: SuperPool.withdraw() must withdraw the correct number of assets from the pools in withdrawQueue"
                );
                fl.eq(
                    _afterSP.poolData[i].totalDepositShares,
                    _beforeSP.poolData[i].totalDepositShares -
                        _beforeSP.shareWithdraws[i],
                    "SP-24: SuperPool.withdraw() must withdraw the correct number of shares from the pools in withdrawQueue"
                );
                fl.eq(
                    _afterSP.superPoolShareBalance[i],
                    _beforeSP.superPoolShareBalance[i] -
                        _beforeSP.shareWithdraws[i],
                    "SP-25: SuperPool.withdraw() must deduct the correct number of shares from the SuperPool share balance for the pools in withdrawQueue"
                );
                fl.eq(
                    _afterSP.poolData[i].lastUpdated,
                    uint128(block.timestamp),
                    "SP-26: SuperPool.withdraw() must update lastUpdated to the current block.timestamp for the pools in withdrawQueue"
                );
                if (_beforeSP.pendingInterest[i] > 0) {
                    fl.eq(
                        _afterSP.poolData[i].totalBorrowAssets,
                        _beforeSP.poolData[i].totalBorrowAssets +
                            _beforeSP.pendingInterest[i],
                        "SP-27: SuperPool.withdraw() must credit pendingInterest to the totalBorrows asset balance for pools in withdrawQueue"
                    );
                }
            }
        }
        fl.eq(
            _afterSP.poolAssetBalance,
            _beforeSP.poolAssetBalance - assets,
            "SP-28: SuperPool.withdraw() must transfer the correct number of assets from the base pool for pools in withdrawQueue"
        );
        fl.eq(
            _afterSP.lastTotalAssets,
            _beforeSP.lastTotalAssets - assets,
            "SP-29: SuperPool.withdraw() must decrease the lastTotalAssets by the number of assets consumed"
        );
        fl.lte(
            d.sharesRedeemed,
            _beforeSP.sharesExpectedWithdraw,
            "SP-30: SuperPool.withdraw() must redeem less than or equal to the number of shares predicted by previewWithdraw()"
        );
    }

    // forgefmt: disable-start
    /*********************************************************************************************************************************************/
    /*** Invariant Tests for function redeem                                                                                                   ***/
    /*********************************************************************************************************************************************

        * SP-31: SuperPool.redeem() must credit the correct number of assets to the receiver
        * SP-32: SuperPool.redeem() must deduct the correct number of shares from the owner
        * SP-33: SuperPool.redeem() must withdraw the correct number of assets from the pools in withdrawQueue
        * SP-34: SuperPool.redeem() must withdraw the correct number of shares from the pools in withdrawQueue
        * SP-35: SuperPool.redeem() must deduct the correct number of shares from the SuperPool share balance for the pools in withdrawQueue
        * SP-36: SuperPool.redeem() must update lastUpdated to the current block.timestamp for the pools in withdrawQueue
        * SP-37: SuperPool.redeem() must credit pendingInterest to the totalBorrows asset balance for pools in withdrawQueue
        * SP-38: SuperPool.redeem() must transfer the correct number of assets from the pools in withdrawQueue
        * SP-39: SuperPool.redeem() must decrease the lastTotalAssets by the number of assets consumed
        * SP-40: SuperPool.redeem() must withdraw greater than or equal to the number of assets predicted by previewRedeem()

    /*********************************************************************************************************************************************/
    /*** Assertions that must be true when a user calls redeem                                                                                 ***/
    /*********************************************************************************************************************************************/
    // forgefmt: disable-end

    struct SPRedeemTemps {
        address owner;
        address receiver;
        address asset;
        uint256 assetsWithdrawn;
        MockSuperPool superPool;
    }

    function superPool_redeem(
        uint256 ownerIndexSeed,
        uint256 receiverIndexSeed,
        uint256 poolIndexSeed,
        uint256 shares
    ) public {
        // PRE-CONDITIONS
        SPRedeemTemps memory d;
        d.owner = randomAddress(ownerIndexSeed);
        d.receiver = randomAddress(receiverIndexSeed);
        d.superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        d.asset = d.superPool.asset();

        d.superPool.accrue();

        shares = bound(shares, 0, d.superPool.maxRedeem(d.owner));
        if (shares == 0) return;

        SuperPoolVars memory _beforeSP = __beforeSP(
            d.superPool,
            d.owner,
            d.receiver,
            d.superPool.previewRedeem(shares),
            shares
        );

        // ACTION
        vm.prank(d.owner);
        try d.superPool.redeem(shares, d.receiver, d.owner) returns (
            uint256 assetsWithdrawn
        ) {
            d.assetsWithdrawn = assetsWithdrawn;
        } catch (bytes memory err) {
            bytes4[1] memory errors = [
                SuperPool.SuperPool_NotEnoughLiquidity.selector
            ];
            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            fl.t(expected, FuzzLibString.getRevertMsg(err));
            return;
        }

        // POST-CONDITIONS
        SuperPoolVars memory _afterSP = __afterSP(
            d.superPool,
            d.owner,
            d.receiver,
            d.superPool.previewRedeem(shares),
            shares
        );

        fl.eq(
            _afterSP.assetBalanceReceiver,
            _beforeSP.assetBalanceReceiver + d.assetsWithdrawn,
            "SP-31: SuperPool.redeem() must credit the correct number of assets to the receiver"
        );
        fl.eq(
            _afterSP.shareBalanceFrom,
            _beforeSP.shareBalanceFrom - shares,
            "SP-32: SuperPool.redeem() must deduct the correct number of shares from the owner"
        );

        for (uint256 i = 0; i < _beforeSP.assetWithdraws.length; i++) {
            if (_beforeSP.assetWithdraws[i] == 0) break;

            if (
                _afterSP.poolData[i].totalDepositAssets <
                _beforeSP.poolData[i].totalDepositAssets
            ) {
                fl.eq(
                    _afterSP.poolData[i].totalDepositAssets,
                    _beforeSP.poolData[i].totalDepositAssets -
                        _beforeSP.assetWithdraws[i] +
                        _beforeSP.pendingInterest[i],
                    "SP-33: SuperPool.redeem() must withdraw the correct number of assets from the pools in withdrawQueue"
                );
                fl.eq(
                    _afterSP.poolData[i].totalDepositShares,
                    _beforeSP.poolData[i].totalDepositShares -
                        _beforeSP.shareWithdraws[i],
                    "SP-34: SuperPool.redeem() must withdraw the correct number of shares from the pools in withdrawQueue"
                );
                fl.eq(
                    _afterSP.superPoolShareBalance[i],
                    _beforeSP.superPoolShareBalance[i] -
                        _beforeSP.shareWithdraws[i],
                    "SP-35: SuperPool.redeem() must deduct the correct number of shares from the SuperPool share balance for the pools in depositQueue"
                );
                fl.eq(
                    _afterSP.poolData[i].lastUpdated,
                    uint128(block.timestamp),
                    "SP-36: SuperPool.redeem() must update lastUpdated to the current block.timestamp for the pools in withdrawQueue"
                );
                if (_beforeSP.pendingInterest[i] > 0) {
                    fl.eq(
                        _afterSP.poolData[i].totalBorrowAssets,
                        _beforeSP.poolData[i].totalBorrowAssets +
                            _beforeSP.pendingInterest[i],
                        "SP-37: SuperPool.redeem() must credit pendingInterest to the totalBorrows asset balance for pools in withdrawQueue"
                    );
                }
            }
        }
        fl.eq(
            _afterSP.poolAssetBalance,
            _beforeSP.poolAssetBalance - d.assetsWithdrawn,
            "SP-38: SuperPool.redeem() must transfer the correct number of assets from the pools in withdrawQueue"
        );
        fl.eq(
            _afterSP.lastTotalAssets,
            _beforeSP.lastTotalAssets - d.assetsWithdrawn,
            "SP-39: SuperPool.redeem() must decrease the lastTotalAssets by the number of assets consumed"
        );
        fl.gte(
            d.assetsWithdrawn,
            _beforeSP.assetsExpectedRedeem,
            "SP-40: SuperPool.redeem() must withdraw greater than or equal to the number of assets predicted by previewRedeem()"
        );
    }

    // forgefmt: disable-start
    /*********************************************************************************************************************************************/
    /*** Invariant Tests for function accrue                                                                                                   ***/
    /*********************************************************************************************************************************************

        * SP-41: The lastTotalAssets value before calling accrue should always be <= after calling it
        * SP-42: Fee recipient shares after should be greater than or equal to fee recipient shares before

    /*********************************************************************************************************************************************/
    /*** Assertions that must be true when a user calls accrue                                                                                 ***/
    /*********************************************************************************************************************************************/

    struct SPAccrueTemps {
        address sender;
        MockSuperPool superPool;
    }

    function superPool_accrue(
        uint256 senderIndexSeed,
        uint256 poolIndexSeed
    ) public {
        // PRE-CONDITIONS
        SPAccrueTemps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;

        uint256 lastTotalAssetsBefore = d.superPool.lastTotalAssets();
        uint256 feeRecipientSharesBefore = d.superPool.balanceOf(
            d.superPool.feeRecipient()
        );

        // ACTION
        d.superPool.accrue();

        // POST-CONDITIONS
        uint256 lastTotalAssetsAfter = d.superPool.lastTotalAssets();
        uint256 feeRecipientSharesAfter = d.superPool.balanceOf(
            d.superPool.feeRecipient()
        );

        fl.lte(
            lastTotalAssetsBefore,
            lastTotalAssetsAfter,
            "SP-41: The lastTotalAssets value before calling accrue should always be <= after calling it"
        );
        fl.gte(
            feeRecipientSharesAfter,
            feeRecipientSharesBefore,
            "SP-42: Fee recipient shares after should be greater than or equal to fee recipient shares before"
        );
    }
}
