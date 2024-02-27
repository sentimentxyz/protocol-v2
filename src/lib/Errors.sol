// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Errors {
    // [Pool.repay] repay amt is too small
    error ZeroSharesRepay();

    // [Pool.borrow] borrow amt is too small
    error ZeroSharesBorrow();

    // [PositionManager.borrow] pool was not deployed via the protocol pool factory
    error UnknownPool();

    // [PositionManager.toggleAuth] only position owners can call this method
    error OnlyPositionOwner();

    // [RiskEngine.setOracle] oracle not recognized by the risk engine
    error UnknownOracle();

    // [BasePosition.exec] exec call failed and returned false
    error ExecFailed();

    // [PositionManager.approve] unknown spender contract for approve action
    error UnknownContract();

    // [PositionManager._process] unrecognized op param in action struct
    error UnknownOperation();

    // [PositionManager.exec] unrecognized target + function selctor for exec action
    error UnknownExecCall();

    // [PositionManager.newPosition] new position address is different from predicted address
    error PositionAddressMismatch();

    // [SingleDebtPosition.borrow] attempt to borrow from more than one pool
    error InvalidBorrow();

    // [SingleDebtPosition.repay] attempt to repay to the wrong pool
    error InvalidRepay();

    // [SuperPool.setPoolCap] pool and superpool have different underlying assets
    error InvalidPoolAsset();

    // [PositionManager.process | PositionManager.processBatch | PositionManager.liquidate]
    // final position state violates risk thresholds
    error HealthCheckFailed();

    // [RiskEngine.isPositionHealthy | RiskEngine.isValidLiquidation]
    // missing health check implementation config for the given position type
    error NoHealthCheckImpl();

    // [IHealthCheck.isValidLiquidation] liquidation violates close factor by repaying too much debt
    error RepaidTooMuchDebt();

    // [PositionManager.liquidate] invalid liquidation params caused IHealthCheck.isValidLiquidation
    // to return false
    error InvalidLiquidation();

    // [PositionManager.newPosition] missing upgradeable beacon config for given position type
    error NoPositionBeacon();

    // [Pool.borrow | Pool.repay | BasePosition.onlyPositionManager modifier]
    // only position manager is authzd to call this function
    error OnlyPositionManager();

    // [Superpool.poolDeposit | SuperPool.poolWithdraw]
    // only superpool owner and allocator can deposit/withdraw from pool
    error OnlyAllocatorOrOwner();

    // [RiskEngine.setLtv]
    // attempt to set ltv beyond protocol limits set in the risk engine
    error OutsideGlobalLtvLimits();

    // [IHealthCheck.isValidLiquidation] collateral seized is more than max liquidation discount
    error SeizedTooMuchCollateral();

    // [PositionManager.liquidate] attempt to liquidate healthy position
    error LiquidateHealthyPosition();

    // [PositionManager._process] caller is not authorized to operate on the given position
    error UnauthorizedAction();

    // [RiskEngine.setLtv] only pool owners can call this function
    error onlyPoolOwner();
}
