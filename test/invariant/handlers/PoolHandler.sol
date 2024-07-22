// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {PoolProperties} from "../properties/PoolProperties.sol";
import {Vm} from "forge-std/Test.sol";
import {FuzzLibString} from "@fuzzlib/FuzzLibString.sol";
import {Pool} from "src/Pool.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract PoolHandler is PoolProperties {
    struct ApproveTemps {
        address spender;
        address owner;
        uint256 poolId;
    }

    function pool_approve(
        uint256 spenderIndexSeed,
        uint256 ownerIndexSeed,
        uint256 poolIdIndexSeed,
        uint256 amount
    ) public {
        ApproveTemps memory d;
        d.spender = randomAddress(spenderIndexSeed);
        d.owner = randomAddress(ownerIndexSeed);
        d.poolId = randomPoolId(poolIdIndexSeed);

        Vars memory _before = __before(d.poolId, d.owner, address(0));

        amount = bound(
            amount,
            0,
            IERC20(_before.poolData.asset).balanceOf(d.owner)
        );

        vm.prank(d.owner);
        pool.approve(d.spender, d.poolId, amount);
    }

    struct SetOperatorTemps {
        address spender;
        address owner;
    }

    function pool_setOperator(
        uint256 spenderIndexSeed,
        uint256 ownerIndexSeed,
        bool approved
    ) public {
        SetOperatorTemps memory d;
        d.spender = randomAddress(spenderIndexSeed);
        d.owner = randomAddress(ownerIndexSeed);

        vm.prank(d.owner);
        pool.setOperator(d.spender, approved);
    }

    // forgefmt: disable-start
    /**************************************************************************************************************************/
    /*** Invariant Tests for function deposit                                                                               ***/
    /**************************************************************************************************************************

        * PO-01: Pool.deposit() must increase poolId assets by assets and pending interest
        * PO-02: Pool.deposit() must increase poolId shares by sharesDeposited
        * PO-03: Pool.deposit() must consume the correct number of assets
        * PO-04: Pool.deposit() must credit the correct number of shares to receiver
        * PO-05: Pool.deposit() must transfer the correct number of assets to pool
        * PO-06: Pool.deposit() must update lastUpdated to the current block.timestamp
        * PO-07: Pool.deposit() must credit pendingInterest to the totalBorrows asset balance for poolID

    /**************************************************************************************************************************/
    /*** Assertions that must be true when a user calls deposit                                                             ***/
    /**************************************************************************************************************************/
    // forgefmt: disable-end

    struct DepositTemps {
        address from;
        address receiver;
        uint256 poolId;
        uint256 pendingInterest;
        uint256 sharesDeposited;
    }

    function pool_deposit(
        uint256 fromIndexSeed,
        uint256 receiverIndexSeed,
        uint256 poolIdIndexSeed,
        uint256 assets
    ) public {
        // PRE-CONDITIONS
        DepositTemps memory d;
        d.from = randomAddress(fromIndexSeed);
        d.receiver = randomAddress(receiverIndexSeed);
        d.poolId = randomPoolId(poolIdIndexSeed);

        Vars memory _before = __before(d.poolId, d.from, d.receiver);

        assets = bound(
            assets,
            1,
            IERC20(_before.poolData.asset).balanceOf(d.from)
        );

        (d.pendingInterest, ) = pool.mockSimulateAccrue(d.poolId);

        vm.prank(d.from);
        IERC20(_before.poolData.asset).approve(address(pool), assets);

        // ACTION
        vm.prank(d.from);
        try pool.deposit(d.poolId, assets, d.receiver) returns (
            uint256 sharesDeposited
        ) {
            d.sharesDeposited = sharesDeposited;
        } catch (bytes memory err) {
            bytes4[3] memory errors = [
                Pool.Pool_PoolPaused.selector,
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
        Vars memory _after = __after(d.poolId, d.from, d.receiver);

        fl.eq(
            _after.poolData.totalDepositAssets,
            _before.poolData.totalDepositAssets + assets + d.pendingInterest,
            "PO-01: Pool.deposit() must increase poolId assets by assets and pending interest"
        );
        fl.eq(
            _after.poolData.totalDepositShares,
            _before.poolData.totalDepositShares + d.sharesDeposited,
            "PO-02: Pool.deposit() must increase poolId shares by sharesDeposited"
        );
        fl.eq(
            _after.fromAssetBalance,
            _before.fromAssetBalance - assets,
            "PO-03: Pool.deposit() must consume the correct number of assets"
        );
        fl.eq(
            _after.receiverShareBalance,
            _before.receiverShareBalance + d.sharesDeposited,
            "PO-04: Pool.deposit() must credit the correct number of shares to receiver"
        );
        fl.eq(
            _after.poolAssetBalance,
            _before.poolAssetBalance + assets,
            "PO-05: Pool.deposit() must transfer the correct number of assets to pool"
        );
        fl.eq(
            _after.poolData.lastUpdated,
            uint128(block.timestamp),
            "PO-06: Pool.deposit() must update lastUpdated to the current block.timestamp"
        );
        if (d.pendingInterest > 0) {
            fl.eq(
                _after.poolData.totalBorrowAssets,
                _before.poolData.totalBorrowAssets +
                    uint128(d.pendingInterest),
                "PO-07: Pool.deposit() must credit pendingInterest to the totalBorrows asset balance for poolID"
            );
        }
    }

    // forgefmt: disable-start
    /**************************************************************************************************************************/
    /*** Invariant Tests for function redeem                                                                                ***/
    /**************************************************************************************************************************

        * PO-08: Pool.redeem() must decrease poolId assets by assetsRedeemed + pendingInterest
        * PO-09: Pool.redeem() must decrease poolId shares by shares amount
        * PO-10: Pool.redeem() must credit the correct number of assets to receiver
        * PO-11: Pool.redeem() must consume the correct number of shares from receiver
        * PO-12: Pool.redeem() must transfer the correct number of assets to receiver
        * PO-13: Pool.redeem() must update lastUpdated to the current block.timestamp
        * PO-14: Pool.redeem() must credit pendingInterest to the totalBorrows asset balance for poolID

    /**************************************************************************************************************************/
    /*** Assertions that must be true when a user calls redeem                                                              ***/
    /**************************************************************************************************************************/
    // forgefmt: disable-end

    struct RedeemTemps {
        address sender;
        address owner;
        address receiver;
        uint256 poolId;
        uint256 pendingInterest;
        uint256 sharesRedeemed;
    }

    function pool_withdraw(
        uint256 senderIndexSeed,
        uint256 ownerIndexSeed,
        uint256 receiverIndexSeed,
        uint256 poolIdIndexSeed,
        uint256 assets
    ) public {
        // PRE-CONDITIONS
        RedeemTemps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.owner = randomAddress(ownerIndexSeed);
        d.receiver = randomAddress(receiverIndexSeed);
        d.poolId = randomPoolId(poolIdIndexSeed);

        Vars memory _before = __before(d.poolId, d.owner, d.receiver);

        if (pool.balanceOf(d.owner, d.poolId) == 0) return;
        assets = bound(assets, 1, pool.getAssetsOf(d.poolId, d.owner));

        if (
            pool.convertToAssets(
                IERC20(_before.poolData.asset).balanceOf(address(pool)),
                _before.poolData.totalDepositAssets,
                _before.poolData.totalDepositShares
             ) <
            assets
        ) return;

        if (
            _before.poolData.totalDepositAssets -
                _before.poolData.totalBorrowAssets ==
            0
        ) return;

        (d.pendingInterest, ) = pool.mockSimulateAccrue(d.poolId);

        if (
            pool.convertToAssets(
                IERC20(_before.poolData.asset).allowance(d.owner, d.sender),
                _before.poolData.totalDepositAssets,
                _before.poolData.totalDepositShares
             ) < assets
        ) {
            d.sender = d.owner;
        }

        // ACTION
        vm.prank(d.sender);
        try pool.withdraw(d.poolId, assets, d.receiver, d.owner) returns (
            uint256 sharesRedeemed
        ) {
            d.sharesRedeemed = sharesRedeemed;
        } catch (bytes memory err) {
            bytes4[2] memory errors = [
                Pool.Pool_ZeroShareRedeem.selector,
                Pool.Pool_InsufficientWithdrawLiquidity.selector
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
        Vars memory _after = __after(d.poolId, d.owner, d.receiver);

        fl.eq(
            _after.poolData.totalDepositAssets,
            _before.poolData.totalDepositAssets +
                d.pendingInterest -
                assets,
            "PO-08: Pool.redeem() must decrease poolId assets by assetsRedeemed + pendingInterest"
        );
        fl.eq(
            _after.poolData.totalDepositShares,
            _before.poolData.totalDepositShares - d.sharesRedeemed,
            "PO-09: Pool.redeem() must decrease poolId shares by shares amount"
        );
        fl.eq(
            _after.receiverAssetBalance,
            _before.receiverAssetBalance + assets,
            "PO-10: Pool.redeem() must credit the correct number of assets to receiver"
        );
        fl.eq(
            _after.fromShareBalance,
            _before.fromShareBalance - d.sharesRedeemed,
            "PO-11: Pool.redeem() must consume the correct number of shares from receiver"
        );
        fl.eq(
            _after.poolAssetBalance,
            _before.poolAssetBalance - assets,
            "PO-12: Pool.redeem() must transfer the correct number of assets to receiver"
        );
        fl.eq(
            _after.poolData.lastUpdated,
            uint128(block.timestamp),
            "PO-13: Pool.redeem() must update lastUpdated to the current block.timestamp"
        );
        if (d.pendingInterest > 0) {
            fl.eq(
                _after.poolData.totalBorrowAssets,
                _before.poolData.totalBorrowAssets +
                    uint128(d.pendingInterest),
                "PO-14: Pool.redeem() must credit pendingInterest to the totalBorrows asset balance for poolID"
            );
        }
    }

    // forgefmt: disable-start
    /*********************************************************************************************************************************************/
    /*** Invariant Tests for function accrue                                                                                                   ***/
    /*********************************************************************************************************************************************

        * PO-15: The pool.totalAssets.assets value before calling accrue should always be <= after calling it
        * PO-16: The pool.totalBorrows.assets value before calling accrue should always be <= after calling it
        * PO-17: Fee recipient shares after should be greater than or equal to fee recipient shares before

    /*********************************************************************************************************************************************/
    /*** Assertions that must be true when a user calls accrue                                                                                 ***/
    /*********************************************************************************************************************************************/

    struct PAccrueTemps {
        address sender;
        uint256 poolId;
    }

    function pool_accrue(
        uint256 senderIndexSeed,
        uint256 poolIndexSeed
    ) public {
        // PRE-CONDITIONS
        PAccrueTemps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.poolId = randomPoolId(poolIndexSeed);

        Vars memory _before = __before(d.poolId, d.sender, address(0));

        // ACTION
        pool.accrue(d.poolId);

        // POST-CONDITIONS
        Vars memory _after = __after(d.poolId, d.sender, address(0));

        fl.lte(
            _before.poolData.totalDepositAssets,
            _after.poolData.totalDepositAssets,
            "PO-15: The pool.totalAssets.assets value before calling accrue should always be <= after calling it"
        );
        fl.lte(
            _before.poolData.totalBorrowAssets,
            _after.poolData.totalBorrowAssets,
            "PO-16: The pool.totalBorrows.assets value before calling accrue should always be <= after calling it"
        );
        fl.gte(
            _after.feeRecipientShareBalance,
            _before.feeRecipientShareBalance,
            "PO-17: Fee recipient shares after should be greater than or equal to fee recipient shares before"
        );
    }
}
