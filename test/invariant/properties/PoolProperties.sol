// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { BeforeAfter } from "../helpers/BeforeAfter.sol";

import { FuzzLibString } from "@fuzzlib/FuzzLibString.sol";
import { Vm } from "forge-std/Test.sol";
import { Pool } from "src/Pool.sol";

import { Action, Operation, PositionManager } from "src/PositionManager.sol";
import { SuperPool } from "src/SuperPool.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract PoolProperties is BeforeAfter {
    using Math for uint256;

    /// @notice Verifies position debt value is 0 or greater than or equal to MIN_DEBT
    // function pool_PO_18() public {
    //     for (uint256 i = 0; i < users.length; i++) {
    //         for (uint256 j = 0; j < positionManager.positionsLength(users[i]); j++) {
    //             (uint256 userDebtValue,,) = riskModule.getDebtValue(positionManager.positionsOf(users[i], j));
    //             fl.t(
    //                 userDebtValue == 0 || userDebtValue >= riskModule.MIN_DEBT(),
    //                 "PO-18: User debt value should be equal to 0 or greater than or equal to MIN_DEBT"
    //             );
    //         }
    //     }
    // }

    /// @notice Verifies that minReqAssetValue is greater than position debt value
    function pool_PO_19() public {
        for (uint256 i = 0; i < users.length; i++) {
            for (
                uint256 j = 0;
                j < positionManager.positionsLength(users[i]);
                j++
            ) {
                address position = positionManager.positionsOf(users[i], j);
                (
                    ,
                    address[] memory positionAssets,
                    uint256[] memory positionAssetData
                ) = riskModule.getAssetValue(position);
                (
                    uint256 totalDebtValue,
                    uint256[] memory debtPools,
                    uint256[] memory debtValueForPool
                ) = riskModule.getDebtValue(position);

                // if (totalAssetValue == 0) return;
                if (totalDebtValue == 0) return;
                uint256 minReqAssetValue = riskModule.getMinReqAssetValue(
                    debtPools,
                    debtValueForPool,
                    positionAssets,
                    positionAssetData,
                    position
                );

                fl.gt(
                    minReqAssetValue,
                    totalDebtValue,
                    "PO-19: Min Required Position Asset Value should be greater than total position debt value"
                );
            }
        }
    }

    /// @notice Verifies total pool assets denominated in shares is equal to the total user assets denominated in shares
    function pool_PO_20() public {
        for (uint256 poolId; poolId < poolIds.length; poolId++) {
            uint256 usersTotalAssets;
            for (uint256 user = 0; user < users.length; user++) {
                usersTotalAssets += pool.balanceOf(users[user], poolIds[poolId]);
            }
            usersTotalAssets += pool.balanceOf(address(superPool1), poolIds[poolId]);
            usersTotalAssets += pool.balanceOf(address(superPool2), poolIds[poolId]);
            Pool.PoolData memory poolData = pool.getPoolData(poolIds[poolId]);
            fl.eq(
                usersTotalAssets,
                poolData.totalDepositShares,
                "PO-20: The pool.totalAssets.shares values should always equal the sum of the shares of all users"
            );
        }
    }

    /// @notice Verifies total pool borrows denominated in shares is equal to the total user assets denominated in
    /// shares
    function pool_PO_21() public {
        for (uint256 poolId; poolId < poolIds.length; poolId++) {
            uint256 positionTotalBorrows;
            for (uint256 user; user < users.length; user++) {
                for (uint256 position; position < positionManager.positionsLength(users[user]); position++) {
                    positionTotalBorrows +=
                        pool.borrowSharesOf(poolIds[poolId], positionManager.positionsOf(users[user], position));
                }
            }
            Pool.PoolData memory poolData = pool.getPoolData(poolIds[poolId]);
            fl.eq(
                positionTotalBorrows,
                poolData.totalBorrowShares,
                "PO-21: The pool.totalBorrows.shares values should always equal the sum of the borrow share balances of all borrowers"
            );
        }
    }
}
