// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { BeforeAfter } from "../helpers/BeforeAfter.sol";

import { FuzzLibString } from "@fuzzlib/FuzzLibString.sol";
import { Vm } from "forge-std/Test.sol";
import { Pool } from "src/Pool.sol";
import { Position } from "src/Position.sol";
import { Action, AssetData, DebtData, Operation, PositionManager } from "src/PositionManager.sol";
import { PortfolioLens } from "src/lens/PortfolioLens.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

abstract contract PositionManagerHandler is BeforeAfter {
    using Math for uint256;

    // forgefmt: disable-start
    /**************************************************************************************************************************/
    /*** Invariant Tests for function newPosition                                                                           ***/
    /**************************************************************************************************************************

        * PM-01: PositionManager.newPosition() should set auth to true for owner
        * PM-02: PositionManager.newPosition() should set ownerOf position to owner        

    /**************************************************************************************************************************/
    /*** Assertions that must be true when a user calls newPosition                                                         ***/
    /**************************************************************************************************************************/
    // forgefmt: disable-end
    struct NewPositionTemps {
        address sender;
        address owner;
        bytes data;
        address position;
        Action action;
    }

    function positionManager_newPosition(uint256 senderIndexSeed, uint256 ownerIndexSeed, bytes32 salt) public {
        // PRE-CONDITIONS
        NewPositionTemps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.owner = randomAddress(ownerIndexSeed);
        d.data = abi.encodePacked(d.owner, salt);
        (d.position,) = portfolioLens.predictAddress(d.owner, salt);

        for (uint256 i = 0; i < positionManager.positionsLength(d.owner); i++) {
            if (positionManager.positionsOf(d.owner, i) == d.position) return;
        }

        d.action = Action({ op: Operation.NewPosition, data: d.data });

        // ACTION
        vm.prank(d.owner);
        try positionManager.process(d.position, d.action) { }
        catch (bytes memory err) {
            bytes4[2] memory errors = [
                PositionManager.PositionManager_HealthCheckFailed.selector,
                PositionManager.PositionManager_PredictedPositionMismatch.selector
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
        positionManager.setPositionsOf(d.owner, d.position);

        PositionManagerVars memory _afterPM = __afterPM(d.owner, address(0), d.position, address(asset1), 0);

        fl.eq(_afterPM.isAuth, true, "PM-01: PositionManager.newPosition() should set auth to true for owner");
        fl.eq(_afterPM.ownerOf, d.owner, "PM-02: PositionManager.newPosition() should set ownerOf position to owner");
    }

    // forgefmt: disable-start
    /**************************************************************************************************************************/
    /*** Invariant Tests for function deposit                                                                               ***/
    /**************************************************************************************************************************

        * PM-03: PositionManager.deposit() must consume the correct amount of assets        

    /**************************************************************************************************************************/
    /*** Assertions that must be true when a user calls deposit                                                             ***/
    /**************************************************************************************************************************/
    // forgefmt: disable-end

    struct PmDepositTemps {
        address sender;
        address owner;
        bytes data;
        address asset;
        uint256 assetValue;
        address position;
        Action action;
    }

    function positionManager_deposit(
        uint256 senderIndexSeed,
        uint256 ownerIndexSeed,
        uint256 assetIndexSeed,
        uint256 positionIndexSeed,
        uint256 amount
    ) public {
        // PRE-CONDITIONS
        PmDepositTemps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.owner = randomAddress(ownerIndexSeed);
        d.asset = randomToken(assetIndexSeed);
        d.position = randomPosition(d.owner, positionIndexSeed);

        if (d.position == address(0)) return;

        amount = bound(amount, 1, IERC20(d.asset).balanceOf(d.owner));

        PositionManagerVars memory _beforePM = __beforePM(d.owner, address(0), d.position, d.asset, 0);

        d.data = abi.encodePacked(d.asset, amount);
        d.action = Action({ op: Operation.Deposit, data: d.data });

        // ACTION
        vm.prank(d.owner);
        IERC20(d.asset).approve(address(positionManager), amount);

        vm.prank(d.owner);
        try positionManager.process(d.position, d.action) { }
        catch (bytes memory err) {
            bytes4[1] memory errors = [PositionManager.PositionManager_HealthCheckFailed.selector];
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
        PositionManagerVars memory _afterPM = __afterPM(d.owner, address(0), d.position, d.asset, 0);

        fl.eq(
            _afterPM.fromAssetBalance,
            _beforePM.fromAssetBalance - amount,
            "PM-03: PositionManager.deposit() must consume the correct amount of assets"
        );
    }

    // forgefmt: disable-start
    /**************************************************************************************************************************/
    /*** Invariant Tests for function transfer                                                                              ***/
    /**************************************************************************************************************************

        * PM-04: PositionManager.transfer() must consume asset amount from position
        * PM-05: PositionManager.transfer() must credit asset amount to recipient        

    /**************************************************************************************************************************/
    /*** Assertions that must be true when a user calls transfer                                                            ***/
    /**************************************************************************************************************************/
    // forgefmt: disable-end

    struct TransferTemps {
        address sender;
        address owner;
        address recipient;
        bytes data;
        address asset;
        address position;
        Action action;
    }

    function positionManager_transfer(
        uint256 senderIndexSeed,
        uint256 ownerIndexSeed,
        uint256 recipientIndexSeed,
        uint256 assetIndexSeed,
        uint256 positionIndexSeed,
        uint256 amount
    ) public {
        // PRE-CONDITIONS
        TransferTemps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.owner = randomAddress(ownerIndexSeed);
        d.recipient = randomAddress(recipientIndexSeed);
        d.asset = randomToken(assetIndexSeed);
        d.position = randomPosition(d.owner, positionIndexSeed);

        if (d.position == address(0)) return;

        PositionManagerVars memory _before = __beforePM(d.owner, d.recipient, d.position, d.asset, 0);

        amount = bound(amount, 0, IERC20(d.asset).balanceOf(d.position) - _before.positionDebtValue);

        d.data = abi.encodePacked(d.recipient, d.asset, amount);
        d.action = Action({ op: Operation.Transfer, data: d.data });

        // ACTION
        vm.prank(d.owner);
        IERC20(d.asset).approve(address(positionManager), amount);

        vm.prank(d.owner);
        try positionManager.process(d.position, d.action) { }
        catch (bytes memory err) {
            bytes4[2] memory errors = [
                PositionManager.PositionManager_HealthCheckFailed.selector,
                PositionManager.PositionManager_TransferUnknownAsset.selector
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
        PositionManagerVars memory _after = __afterPM(d.owner, d.recipient, d.position, d.asset, 0);

        fl.eq(
            _after.positionAssetBalance,
            _before.positionAssetBalance - amount,
            "PM-04: PositionManager.transfer() must consume asset amount from position"
        );
        fl.eq(
            _after.recipientAssetBalance,
            _before.recipientAssetBalance + amount,
            "PM-05: PositionManager.transfer() must credit asset amount to recipient"
        );
    }

    // forgefmt: disable-start
    /**************************************************************************************************************************/
    /*** Invariant Tests for function borrow                                                                                ***/
    /**************************************************************************************************************************

        * PM-06: PositionManager.borrow() must credit amount of assets to poolId total borrow asset balance
        * PM-07: PositionManager.borrow() must credit amount of shares to poolId total borrow share balance
        * PM-08: PositionManager.borrow() must credit amount of shares to poolId position share balance
        * PM-09: PositionManager.borrow() must credit fee amount to feeRecipient
        * PM-10: PositionManager.borrow() must credit the correct number of assets to position
        * PM-11: PositionManager.borrow() must add poolId to debtPools
        * PM-12: Position debt pools should be less than or equal to max debt pools
        
    /**************************************************************************************************************************/
    /*** Assertions that must be true when a user calls borrow                                                              ***/
    /**************************************************************************************************************************/
    // forgefmt: disable-end

    struct BorrowTemps {
        address sender;
        address owner;
        address recipient;
        bytes data;
        uint256 poolId;
        uint256 fee;
        address asset;
        uint256 debtValue;
        address payable position;
        uint256 shares;
        uint256[] debtPools;
        Action action;
    }

    function positionManager_borrow(
        uint256 senderIndexSeed,
        uint256 ownerIndexSeed,
        uint256 recipientIndexSeed,
        uint256 poolIdIndexSeed,
        uint256 positionIndexSeed,
        uint256 amount
    ) public {
        // PRE-CONDITIONS
        BorrowTemps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.owner = randomAddress(ownerIndexSeed);
        d.recipient = randomAddress(recipientIndexSeed);
        d.poolId = randomPoolId(poolIdIndexSeed);
        d.position = randomPosition(d.owner, positionIndexSeed);

        if (d.position == address(0)) return;

        pool.accrue(d.poolId);

        Vars memory _beforePool = __before(d.poolId, d.owner, d.recipient);
        d.asset = _beforePool.poolData.asset;
        PositionManagerVars memory _beforePM = __beforePM(d.owner, d.recipient, d.position, d.asset, d.poolId);

        amount = bound(amount, 0, pool.balanceOf(d.owner, d.poolId));
        if (amount == 0) return;
        if (IERC20(_beforePool.poolData.asset).balanceOf(address(pool)) < amount) return;

        d.shares = pool.convertToSharesRounding(
                amount, 
                _beforePool.poolData.totalBorrowAssets, 
                _beforePool.poolData.totalBorrowShares,
                Math.Rounding.Up
            );

        d.fee = amount.mulDiv(_beforePool.poolData.originationFee, 1e18);

        d.data = abi.encodePacked(d.poolId, amount);
        d.action = Action({ op: Operation.Borrow, data: d.data });

        // ACTION
        vm.prank(d.owner);
        IERC20(d.asset).approve(address(positionManager), amount);

        vm.prank(d.owner);
        try positionManager.process(d.position, d.action) { }
        catch (bytes memory err) {
            bytes4[3] memory errors = [
                PositionManager.PositionManager_HealthCheckFailed.selector,
                PositionManager.PositionManager_UnknownPool.selector,
                PositionManager.PositionManager_AddUnknownToken.selector
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
        Vars memory _afterPool = __after(d.poolId, d.owner, d.recipient);
        PositionManagerVars memory _afterPM = __afterPM(d.owner, d.recipient, d.position, d.asset, d.poolId);

        fl.eq(
            _afterPool.poolData.totalBorrowAssets,
            _beforePool.poolData.totalBorrowAssets + amount,
            "PM-06: PositionManager.borrow() must credit amount of assets to poolId total borrow asset balance"
        );
        fl.eq(
            _afterPool.poolData.totalBorrowShares,
            _beforePool.poolData.totalBorrowShares + d.shares,
            "PM-07: PositionManager.borrow() must credit amount of shares to poolId total borrow share balance"
        );
        fl.eq(
            _afterPM.positionBorrowShares,
            _beforePM.positionBorrowShares + d.shares,
            "PM-08: PositionManager.borrow() must credit amount of shares to poolId position share balance"
        );
        fl.eq(
            _afterPool.feeRecipientAssetBalance,
            _beforePool.feeRecipientAssetBalance + d.fee,
            "PM-09: PositionManager.borrow() must credit fee amount to feeRecipient"
        );
        fl.eq(
            _afterPM.positionAssetBalance,
            _beforePM.positionAssetBalance + amount - d.fee,
            "PM-10: PositionManager.borrow() must credit the correct number of assets to position"
        );
        d.debtPools = Position(d.position).getDebtPools();
        bool poolAdded = false;
        for (uint256 i = 0; i < d.debtPools.length; i++) {
            if (d.poolId == d.debtPools[i]) {
                poolAdded = true;
                break;
            } else {
                continue;
            }
        }
        fl.t(poolAdded, "PM-11: PositionManager.borrow() must add poolId to debtPools");
        fl.lte(
            d.debtPools.length,
            Position(d.position).MAX_DEBT_POOLS(),
            "PM-12: Position debt pools should be less than or equal to max debt pools"
        );
    }

    // forgefmt: disable-start
    /**************************************************************************************************************************/
    /*** Invariant Tests for function repay                                                                                 ***/
    /**************************************************************************************************************************

        * PM-13: PositionManager.repay() must credit assets to pool
        * PM-14: PositionManager.repay() must consume asset amount from position
        * PM-15: PositionManager.repay() must consume amount of assets from poolId total borrow asset balance
        * PM-16: PositionManager.repay() must consume amount of shares from poolId total borrow share balance
        * PM-17: PositionManager.repay() must consume amount of shares from poolId position share balance
        * PM-18: PositionManager.repay() must delete poolId from debtPools if position has no borrows
        
    /**************************************************************************************************************************/
    /*** Assertions that must be true when a user calls repay                                                               ***/
    /**************************************************************************************************************************/
    // forgefmt: disable-end

    struct RepayTemps {
        address sender;
        address owner;
        address recipient;
        bytes data;
        uint256 poolId;
        address asset;
        address payable position;
        uint256 shares;
        uint256[] debtPools;
        Action action;
    }

    function positionManager_repay(
        uint256 senderIndexSeed,
        uint256 ownerIndexSeed,
        uint256 recipientIndexSeed,
        uint256 poolIdIndexSeed,
        uint256 positionIndexSeed,
        uint256 amount
    ) public {
        // PRE-CONDITIONS
        RepayTemps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.owner = randomAddress(ownerIndexSeed);
        d.recipient = randomAddress(recipientIndexSeed);
        d.poolId = randomPoolId(poolIdIndexSeed);
        d.position = randomPosition(d.owner, positionIndexSeed);

        if (d.position == address(0)) return;

        pool.accrue(d.poolId);

        Vars memory _beforePool = __before(d.poolId, d.owner, d.recipient);
        d.asset = _beforePool.poolData.asset;
        PositionManagerVars memory _beforePM = __beforePM(d.owner, d.recipient, d.position, d.asset, d.poolId);

        amount = bound(amount, 0, pool.getBorrowsOf(d.poolId, d.position));
        if (IERC20(d.asset).balanceOf(d.position) < amount) return;
        if (amount == 0) return;

        d.shares = pool.convertToShares(
                amount, 
                _beforePool.poolData.totalBorrowAssets, 
                _beforePool.poolData.totalBorrowShares
            );

        d.data = abi.encodePacked(d.poolId, amount);
        d.action = Action({ op: Operation.Repay, data: d.data });

        // ACTION
        vm.prank(d.owner);
        IERC20(d.asset).approve(address(positionManager), amount);

        vm.prank(d.owner);
        try positionManager.process(d.position, d.action) { }
        catch (bytes memory err) {
            bytes4[1] memory errors = [
                PositionManager.PositionManager_HealthCheckFailed.selector
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
        Vars memory _afterPool = __after(d.poolId, d.owner, d.recipient);
        PositionManagerVars memory _afterPM = __afterPM(d.owner, d.recipient, d.position, d.asset, d.poolId);

        fl.eq(
            _afterPool.poolAssetBalance,
            _beforePool.poolAssetBalance + amount,
            "PM-13: PositionManager.repay() must credit assets to pool"
        );
        fl.eq(
            _afterPM.positionAssetBalance,
            _beforePM.positionAssetBalance - amount,
            "PM-14: PositionManager.repay() must consume asset amount from position"
        );
        fl.eq(
            _afterPool.poolData.totalBorrowAssets,
            _beforePool.poolData.totalBorrowAssets - uint128(amount),
            "PM-15: PositionManager.repay() must consume amount of assets from poolId total borrow asset balance"
        );
        fl.eq(
            _afterPool.poolData.totalBorrowShares,
            _beforePool.poolData.totalBorrowShares - uint128(d.shares),
            "PM-16: PositionManager.repay() must consume amount of shares from poolId total borrow share balance"
        );
        fl.eq(
            _afterPM.positionBorrowShares,
            _beforePM.positionBorrowShares - d.shares,
            "PM-17: PositionManager.repay() must consume amount of shares from poolId position share balance"
        );
        d.debtPools = Position(d.position).getDebtPools();
        bool poolDeleted = true;
        if (pool.getBorrowsOf(d.poolId, d.position) == 0) {
            for (uint256 i = 0; i < d.debtPools.length; i++) {
                if (d.poolId == d.debtPools[i]) {
                    poolDeleted = false;
                    break;
                } else {
                    continue;
                }
            }
            fl.t(
                poolDeleted,
                "PM-18: PositionManager.repay() must delete poolId from debtPools if position has no borrows"
            );
        }
    }

    // forgefmt: disable-start
    /**************************************************************************************************************************/
    /*** Invariant Tests for function addToken                                                                              ***/
    /**************************************************************************************************************************

        * PM-19: PositionManager.addToken() must add asset to position assets list
        * PM-20: Position assets length should be less than or equal to max assets
        
    /**************************************************************************************************************************/
    /*** Assertions that must be true when a user calls addToken                                                            ***/
    /**************************************************************************************************************************/
    // forgefmt: disable-end

    struct AddTokenTemps {
        address sender;
        address owner;
        address payable position;
        address asset;
        bytes data;
        address[] assets;
        Action action;
    }

    function positionManager_addToken(
        uint256 senderIndexSeed,
        uint256 ownerIndexSeed,
        uint256 positionIndexSeed,
        uint256 assetIndexSeed
    ) public {
        // PRE-CONDITIONS
        AddTokenTemps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.owner = randomAddress(ownerIndexSeed);
        d.asset = randomToken(assetIndexSeed);
        d.position = randomPosition(d.owner, positionIndexSeed);

        if (d.position == address(0)) return;

        d.assets = Position(d.position).getPositionAssets();
        for (uint256 i = 0; i < d.assets.length; i++) {
            if (d.assets[i] == d.asset) return;
        }

        d.data = abi.encodePacked(d.asset);
        d.action = Action({ op: Operation.AddToken, data: d.data });

        // ACTION
        vm.prank(d.owner);
        try positionManager.process(d.position, d.action) { }
        catch (bytes memory err) {
            bytes4[1] memory errors = [PositionManager.PositionManager_HealthCheckFailed.selector];
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
        d.assets = Position(d.position).getPositionAssets();

        bool assetAdded = false;
        for (uint256 i = 0; i < d.assets.length; i++) {
            if (d.assets[i] == d.asset) assetAdded = true;
            else continue;
        }
        fl.t(assetAdded, "PM-19: PositionManager.addToken() must add asset to position assets list");

        fl.lte(
            d.assets.length,
            Position(d.position).MAX_ASSETS(),
            "PM-20: Position assets length should be less than or equal to max assets"
        );
    }

    // forgefmt: disable-start
    /**************************************************************************************************************************/
    /*** Invariant Tests for function removeToken                                                                           ***/
    /**************************************************************************************************************************

        * PM-21: PositionManager.removeToken() must remove asset from position assets list
        
    /**************************************************************************************************************************/
    /*** Assertions that must be true when a user calls removeToken                                                         ***/
    /**************************************************************************************************************************/
    // forgefmt: disable-end

    struct RemoveTokenTemps {
        address sender;
        address owner;
        address payable position;
        address asset;
        address[] assets;
        bytes data;
        Action action;
    }

    function positionManager_removeToken(
        uint256 senderIndexSeed,
        uint256 ownerIndexSeed,
        uint256 positionIndexSeed,
        uint256 assetIndexSeed
    ) public {
        // PRE-CONDITIONS
        RemoveTokenTemps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.owner = randomAddress(ownerIndexSeed);
        d.asset = randomToken(assetIndexSeed);
        d.position = randomPosition(d.owner, positionIndexSeed);

        if (d.position == address(0)) return;

        d.data = abi.encodePacked(d.asset);
        d.action = Action({ op: Operation.RemoveToken, data: d.data });

        // ACTION
        vm.prank(d.owner);
        try positionManager.process(d.position, d.action) { }
        catch (bytes memory err) {
            bytes4[1] memory errors = [PositionManager.PositionManager_HealthCheckFailed.selector];
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
        d.assets = Position(d.position).getPositionAssets();

        bool assetRemoved = true;
        for (uint256 i = 0; i < d.assets.length; i++) {
            if (d.assets[i] == d.asset) {
                assetRemoved = false;
                break;
            } else {
                continue;
            }
        }
        fl.t(assetRemoved, "PM-21: PositionManager.removeToken() must remove asset from position assets list");
    }

    struct ProcessBatchTemps {
        address owner;
        address position;
        address recipient;
        address asset;
        bytes data;
        uint256 batchLength;
        uint256 poolId;
        Action[] action;
    }

    function positionManager_processBatch(
        uint256 ownerIndexSeed,
        uint256 recipientIndexSeed,
        uint256 poolIdIndexSeed,
        uint256 assetIndexSeed,
        uint256 positionIndexSeed,
        uint256 batchIndexSeed
    ) public {
        // PRE-CONDITIONS
        ProcessBatchTemps memory d;
        d.owner = randomAddress(ownerIndexSeed);
        d.recipient = randomAddress(recipientIndexSeed);
        d.poolId = randomPoolId(poolIdIndexSeed);
        d.asset = randomToken(assetIndexSeed);
        d.position = randomPosition(d.owner, positionIndexSeed);
        d.batchLength = bound(ownerIndexSeed, 1, 10);

        if (d.position == address(0)) return;

        d.action = randomBatchArray(d.batchLength, d.owner, d.recipient, d.position, batchIndexSeed);

        require(d.action.length > 0);

        // ACTION
        vm.prank(d.owner);
        asset1.approve(address(positionManager), type(uint256).max);
        vm.prank(d.owner);
        asset2.approve(address(positionManager), type(uint256).max);

        vm.prank(d.owner);
        try positionManager.processBatch(d.position, d.action) { }
        catch (bytes memory err) {
            bytes4[17] memory errors = [
                PositionManager.PositionManager_HealthCheckFailed.selector,
                PositionManager.PositionManager_UnknownSpender.selector,
                PositionManager.PositionManager_UnknownPool.selector,
                PositionManager.PositionManager_UnknownSpender.selector,
                PositionManager.PositionManager_OnlyPositionOwner.selector,
                PositionManager.PositionManager_OnlyPositionAuthorized.selector,
                PositionManager.PositionManager_PredictedPositionMismatch.selector,
                Pool.Pool_PoolPaused.selector,
                Pool.Pool_PoolCapExceeded.selector,
                Pool.Pool_NoRateModelUpdate.selector,
                Pool.Pool_PoolAlreadyInitialized.selector,
                Pool.Pool_ZeroSharesRepay.selector,
                Pool.Pool_ZeroSharesBorrow.selector,
                Pool.Pool_ZeroSharesDeposit.selector,
                Pool.Pool_OnlyPoolOwner.selector,
                Pool.Pool_OnlyPositionManager.selector,
                Pool.Pool_TimelockPending.selector
            ];
            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            fl.t(true, FuzzLibString.getRevertMsg(err));
            return;
        }

        for (uint256 i = 0; i < d.action.length; i++) {
            if (d.action[i].op == Operation.Deposit) fl.log("In Deposit");
            else if (d.action[i].op == Operation.Transfer) fl.log("In Transfer");
            else if (d.action[i].op == Operation.Repay) fl.log("In Repay");
            else if (d.action[i].op == Operation.Borrow) fl.log("In Borrow");
            else if (d.action[i].op == Operation.AddToken) fl.log("In AddToken");
            else if (d.action[i].op == Operation.RemoveToken) fl.log("In RemoveToken");
        }
    }

    // forgefmt: disable-start
    /**************************************************************************************************************************/
    /*** Invariant Tests for function liquidate                                                                             ***/
    /**************************************************************************************************************************

        * PM-22: PositionManager.liquidate() must credit the correct number of debt assets to pool
        * PM-23: PositionManager.liquidate() must credit the correct number of assets to liquidator
        * PM-24: PositionManager.liquidate() must credit the correct number of debt assets to owner
        * PM-25: PositionManager.liquidate() must consume the correct number of position assets from position
        * PM-26: Position must be healthy after liquidation
        * PM-27: PositionManager.liquidate() must consume the correct number of assets from the pools in debtData
        * PM-28: PositionManager.liquidate() must consume the correct number of shares from the pools in debtData
        * PM-29: PositionManager.liquidate() must consume amount of shares from poolId position share balance
        * PM-30: PositionManager.liquidate() must update lastUpdated to the current block.timestamp for the pools in debtData
        * PM-31: PositionManager.liquidate() must delete poolId from debtPools if position has no borrows 
        
    /**************************************************************************************************************************/
    /*** Assertions that must be true when a user calls liquidate                                                           ***/
    /**************************************************************************************************************************/
    // forgefmt: disable-end

    struct LiquidationTemps {
        address sender;
        address owner;
        address recipient;
        address payable position;
        uint256 debtAmount;
        uint256 borrowShares;
        uint256[] debtPools;
        PortfolioLens.DebtData[] portfolioDebtData;
        PortfolioLens.AssetData[] portfolioAssetData;
        DebtData[] debtData;
        AssetData[] assetData;
    }

    function positionManager_liquidate(
        uint256 senderIndexSeed,
        uint256 ownerIndexSeed,
        uint256 positionIndexSeed
    ) public {
        // PRE-CONDITIONS
        LiquidationTemps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.owner = randomAddress(ownerIndexSeed);

        d.position = randomLiquidatablePosition(positionIndexSeed);

        if (d.position == address(0)) return;

        d.assetData = constructAssetDataArray(portfolioLens.getAssetData(d.position));
        d.debtData = constructDebtDataArray(portfolioLens.getDebtData(d.position));

        for (uint256 i = 0; i < d.debtData.length; i++) {
            asset1.mint(d.sender, d.debtData[i].amt);
            asset2.mint(d.sender, d.debtData[i].amt);
        }

        LiquidationVars memory _beforeLiq = __beforeLiq(d.debtData, d.assetData, d.sender, d.position);

        // ACTIONS
        vm.prank(d.sender);
        asset1.approve(address(positionManager), type(uint256).max);
        vm.prank(d.sender);
        asset2.approve(address(positionManager), type(uint256).max);

        vm.prank(d.sender);
        try positionManager.liquidate(d.position, d.debtData, d.assetData) { }
        catch (bytes memory err) {
            bytes4[2] memory errors = [
                PositionManager.PositionManager_LiquidateHealthyPosition.selector,
                PositionManager.PositionManager_HealthCheckFailed.selector
            ];
            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            fl.t(false, FuzzLibString.getRevertMsg(err));
            return;
        }

        // POST-CONDITIONS
        LiquidationVars memory _afterLiq = __afterLiq(d.debtData, d.assetData, d.sender, d.position);

        fl.eq(
            _afterLiq.poolAsset1Balance,
            _beforeLiq.poolAsset1Balance + _beforeLiq.totalDebtAsset1,
            "PM-22: PositionManager.liquidate() must credit the correct number of debt assets to pool"
        );
        fl.eq(
            _afterLiq.poolAsset2Balance,
            _beforeLiq.poolAsset2Balance + _beforeLiq.totalDebtAsset2,
            "PM-22: PositionManager.liquidate() must credit the correct number of debt assets to pool"
        );
        fl.eq(
            _afterLiq.liquidatorAsset1Balance,
            _beforeLiq.liquidatorAsset1Balance - _beforeLiq.totalDebtAsset1 + _beforeLiq.totalPositionAsset1
                - _beforeLiq.asset1LiquidationFee,
            "PM-23: PositionManager.liquidate() must credit the correct number of assets to liquidator"
        );
        fl.eq(
            _afterLiq.liquidatorAsset2Balance,
            _beforeLiq.liquidatorAsset2Balance - _beforeLiq.totalDebtAsset2 + _beforeLiq.totalPositionAsset2
                - _beforeLiq.asset2LiquidationFee,
            "PM-23: PositionManager.liquidate() must credit the correct number of assets to liquidator"
        );
        fl.eq(
            _afterLiq.ownerAsset1Balance,
            _beforeLiq.ownerAsset1Balance + _beforeLiq.asset1LiquidationFee,
            "PM-24: PositionManager.liquidate() must credit the correct number of debt assets to owner"
        );
        fl.eq(
            _afterLiq.ownerAsset2Balance,
            _beforeLiq.ownerAsset2Balance + _beforeLiq.asset2LiquidationFee,
            "PM-24: PositionManager.liquidate() must credit the correct number of debt assets to owner"
        );
        fl.eq(
            _afterLiq.positionAsset1Balance,
            _beforeLiq.positionAsset1Balance - _beforeLiq.totalPositionAsset1,
            "PM-25: PositionManager.liquidate() must consume the correct number of position assets from position"
        );
        fl.eq(
            _afterLiq.positionAsset2Balance,
            _beforeLiq.positionAsset2Balance - _beforeLiq.totalPositionAsset2,
            "PM-25: PositionManager.liquidate() must consume the correct number of position assets from position"
        );
        fl.t(riskModule.isPositionHealthy(d.position), "PM-26: Position must be healthy after liquidation");

        d.debtPools = Position(d.position).getDebtPools();

        for (uint256 i = 0; i < d.debtData.length; i++) {
            d.borrowShares = pool.convertToShares(
                d.debtData[i].amt, 
                _beforeLiq.poolData[i].totalBorrowAssets,
                _beforeLiq.poolData[i].totalBorrowShares
            );
            fl.eq(
                _afterLiq.poolData[i].totalBorrowAssets,
                _beforeLiq.poolData[i].totalBorrowAssets - d.debtData[i].amt,
                "PM-27: PositionManager.liquidate() must consume the correct number of assets from the pools in debtData"
            );
            fl.eq(
                _afterLiq.poolData[i].totalBorrowShares,
                _beforeLiq.poolData[i].totalBorrowShares - d.borrowShares,
                "PM-28: PositionManager.liquidate() must consume the correct number of shares from the pools in debtData"
            );
            fl.eq(
                _afterLiq.positionBorrowShares[i],
                _beforeLiq.positionBorrowShares[i] - d.borrowShares,
                "PM-29: PositionManager.liquidate() must consume amount of shares from poolId position share balance"
            );
            fl.eq(
                _afterLiq.poolData[i].lastUpdated,
                uint128(block.timestamp),
                "PM-30: PositionManager.liquidate() must update lastUpdated to the current block.timestamp for the pools in debtData"
            );
            bool poolDeleted = true;
            if (pool.getBorrowsOf(d.debtData[i].poolId, d.position) == 0) {
                for (uint256 j = 0; j < d.debtPools.length; j++) {
                    if (d.debtData[j].poolId == d.debtPools[j]) {
                        poolDeleted = false;
                        break;
                    } else {
                        continue;
                    }
                }
                fl.t(
                    poolDeleted,
                    "PM-31: PositionManager.liquidate() must delete poolId from debtPools if position has no borrows"
                );
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function randomPosition(address owner, uint256 seed) internal view returns (address payable) {
        if (positionManager.positionsLength(owner) == 0) return payable(address(0));
        return payable(positionManager.positionsOf(owner, bound(seed, 0, positionManager.positionsLength(owner) - 1)));
    }

    struct RandomBatchArrayTemps {
        Action[] actions;
        uint256 index;
        uint8 operation;
        bytes data;
        address asset;
        uint256 poolId;
        uint256 amount;
    }

    function randomBatchArray(
        uint256 batchLength,
        address owner,
        address recipient,
        address position,
        uint256 seed
    ) internal view returns (Action[] memory) {
        RandomBatchArrayTemps memory d;
        d.actions = new Action[](batchLength);
        d.index;
        d.operation;
        d.data;
        d.asset;
        d.amount;
        d.poolId;
        for (uint256 i = 0; i < 100; i++) {
            d.operation = uint8(bound(seed + i, 2, 8));

            if (Operation(d.operation) == Operation.Deposit) {
                if (d.actions[batchLength - 1].op != Operation(0)) break;
                d.asset = randomToken(i);
                if (IERC20(d.asset).balanceOf(owner) == 0) continue;
                d.amount = bound(IERC20(d.asset).balanceOf(owner) + i, 1, IERC20(d.asset).balanceOf(owner));

                d.data = abi.encodePacked(d.asset, d.amount);
                d.actions[d.index] = Action({ op: Operation.Deposit, data: d.data });
                d.index++;
            } else if (Operation(d.operation) == Operation.Transfer) {
                if (d.actions[batchLength - 1].op != Operation(0)) break;
                d.asset = randomToken(i);
                d.amount = bound(IERC20(d.asset).balanceOf(position) + i, 0, IERC20(d.asset).balanceOf(position));
                d.data = abi.encodePacked(recipient, d.asset, d.amount);
                d.actions[d.index] = Action({ op: Operation.Transfer, data: d.data });
                d.index++;
            } else if (Operation(d.operation) == Operation.Repay) {
                if (d.actions[batchLength - 1].op != Operation(0)) break;
                d.poolId = randomPoolId(i);
                if (pool.getBorrowsOf(d.poolId, position) == 0) continue;
                d.amount = bound(pool.getBorrowsOf(d.poolId, position) + i, 1, pool.getBorrowsOf(d.poolId, position));
                if (d.amount == 0) continue;
                d.data = abi.encodePacked(d.poolId, d.amount);
                d.actions[d.index] = Action({ op: Operation.Repay, data: d.data });
                d.index++;
            } else if (Operation(d.operation) == Operation.Borrow) {
                if (d.actions[batchLength - 1].op != Operation(0)) break;
                d.poolId = randomPoolId(i);
                d.asset = pool.getPoolAssetFor(d.poolId);
                if (IERC20(d.asset).balanceOf(position) == 0) continue;
                d.amount = bound(IERC20(d.asset).balanceOf(position) + i, 1, IERC20(d.asset).balanceOf(position));
                if (pool.getLiquidityOf(d.poolId) < d.amount) continue;
                d.data = abi.encodePacked(d.poolId, d.amount);
                d.actions[d.index] = Action({ op: Operation.Borrow, data: d.data });
                d.index++;
            } else if (Operation(d.operation) == Operation.AddToken) {
                if (d.actions[batchLength - 1].op != Operation(0)) break;
                d.asset = randomToken(i);
                d.data = abi.encodePacked(d.asset);
                d.actions[d.index] = Action({ op: Operation.AddToken, data: d.data });
                d.index++;
            } else if (Operation(d.operation) == Operation.RemoveToken) {
                if (d.actions[batchLength - 1].op != Operation(0)) break;
                d.asset = randomToken(i);
                d.data = abi.encodePacked(d.asset);
                d.actions[d.index] = Action({ op: Operation.RemoveToken, data: d.data });
                d.index++;
            } else if (Operation(d.operation) == Operation.Approve) {
                if (d.actions[batchLength - 1].op != Operation(0)) break;
                continue;
            }
        }
        return d.actions;
    }

    function randomLiquidatablePosition(uint256 seed) internal view returns (address payable) {
        uint256 count;
        for (uint256 i = 0; i < users.length; i++) {
            for (uint256 j = 0; i < positionManager.positionsLength(users[i]); i++) {
                if (!riskEngine.isPositionHealthy(positionManager.positionsOf(users[i], j))) count++;
            }
        }

        address[] memory positions = new address[](count);
        uint256 index;
        for (uint256 i = 0; i < users.length; i++) {
            for (uint256 j = 0; i < positionManager.positionsLength(users[i]); i++) {
                if (!riskEngine.isPositionHealthy(positionManager.positionsOf(users[i], j))) {
                    positions[index] = positionManager.positionsOf(users[i], j);
                    index++;
                }
            }
        }
        if (positions.length == 0) return payable(address(0));
        return payable(positions[bound(seed, 0, positions.length - 1)]);
    }

    function constructAssetDataArray(PortfolioLens.AssetData[] memory array)
        internal
        pure
        returns (AssetData[] memory)
    {
        AssetData[] memory assetData = new AssetData[](array.length);
        uint256 amount;
        for (uint256 i = 0; i < array.length; i++) {
            amount = bound(amount, array[i].amount / 2, array[i].amount);
            // amount = array[i].amount;
            assetData[i] = AssetData({ asset: array[i].asset, amt: amount });
        }
        return assetData;
    }

    function constructDebtDataArray(PortfolioLens.DebtData[] memory array) internal pure returns (DebtData[] memory) {
        DebtData[] memory debtData = new DebtData[](array.length);
        uint256 amount;
        for (uint256 i = 0; i < array.length; i++) {
            // amount = bound(amount, (array[i].amount * 95e18) / 100e18, array[i].amount);
            amount = array[i].amount;
            debtData[i] = DebtData({ poolId: array[i].poolId, amt: amount });
        }
        return debtData;
    }
}
