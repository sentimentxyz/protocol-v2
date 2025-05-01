// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Pool } from "../Pool.sol";
import { SuperPool } from "../SuperPool.sol";
import { IRateModel } from "../interfaces/IRateModel.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title RateLens
/// @notice View functions to simulate borrow and supply rates for different scenarios
/// @dev Provides projected rate calculations without actually modifying pool state
contract RateLens {
    using Math for uint256;

    // @notice Address to the protocol's pool instance
    Pool public immutable POOL;

    // @param pool Address to the protocol's pool instance
    constructor(address pool) {
        POOL = Pool(pool);
    }

    /// @notice Calculates the projected borrow rate if x amount is borrowed
    /// @param poolId Id of the underlying pool
    /// @param borrowAmount The amount to borrow
    /// @return The projected borrow rate (in 1e18)
    function projectedBorrowRateOnBorrow(uint256 poolId, uint256 borrowAmount) external view returns (uint256) {
        IRateModel irm = IRateModel(POOL.getRateModelFor(poolId));

        uint256 totalBorrows = POOL.getTotalBorrows(poolId);
        uint256 totalAssets = POOL.getTotalAssets(poolId);

        // Simulate the state after borrowing
        uint256 newBorrows = totalBorrows + borrowAmount;

        // Calculate the borrow rate after the hypothetical borrow
        return irm.getInterestRate(newBorrows, totalAssets);
    }

    /// @notice Calculates the projected borrow rate if x amount is repaid
    /// @param poolId Id of the underlying pool
    /// @param repayAmount The amount to repay
    /// @return The projected borrow rate (in 1e18)
    function projectedBorrowRateOnRepay(uint256 poolId, uint256 repayAmount) external view returns (uint256) {
        IRateModel irm = IRateModel(POOL.getRateModelFor(poolId));

        uint256 totalBorrows = POOL.getTotalBorrows(poolId);
        uint256 totalAssets = POOL.getTotalAssets(poolId);

        // Simulate the state after repaying
        uint256 newBorrows = totalBorrows > repayAmount ? totalBorrows - repayAmount : 0;

        // Calculate the borrow rate after the hypothetical repay
        return irm.getInterestRate(newBorrows, totalAssets);
    }

    /// @notice Calculates the projected supply rate if x amount is deposited
    /// @param poolId Id of the underlying pool
    /// @param depositAmount The amount to deposit
    /// @return The projected supply rate (in 1e18)
    function projectedSupplyRateOnDeposit(uint256 poolId, uint256 depositAmount) public view returns (uint256) {
        IRateModel irm = IRateModel(POOL.getRateModelFor(poolId));

        uint256 totalBorrows = POOL.getTotalBorrows(poolId);
        uint256 totalAssets = POOL.getTotalAssets(poolId);

        // Simulate the state after depositing
        uint256 newTotalAssets = totalAssets + depositAmount;

        // Calculate the borrow rate with the new assets amount
        uint256 borrowRate = irm.getInterestRate(totalBorrows, newTotalAssets);

        // Calculate new utilization rate
        uint256 utilizationRate = newTotalAssets == 0 ? 0 : totalBorrows.mulDiv(1e18, newTotalAssets, Math.Rounding.Up);

        // Supply rate = borrow rate * utilization rate
        return borrowRate.mulDiv(utilizationRate, 1e18);
    }

    /// @notice Calculates the projected supply rate if x amount is withdrawn
    /// @param poolId Id of the underlying pool
    /// @param withdrawAmount The amount to withdraw
    /// @return The projected supply rate (in 1e18)
    function projectedSupplyRateOnWithdraw(uint256 poolId, uint256 withdrawAmount) public view returns (uint256) {
        IRateModel irm = IRateModel(POOL.getRateModelFor(poolId));

        uint256 totalBorrows = POOL.getTotalBorrows(poolId);
        uint256 totalAssets = POOL.getTotalAssets(poolId);

        // Ensure we don't withdraw more than available assets
        uint256 actualWithdraw = withdrawAmount > totalAssets ? totalAssets : withdrawAmount;

        // Simulate the state after withdrawing
        uint256 newTotalAssets = totalAssets > actualWithdraw ? totalAssets - actualWithdraw : 0;

        // Calculate the borrow rate with the new assets amount
        uint256 borrowRate = irm.getInterestRate(totalBorrows, newTotalAssets);

        // Calculate new utilization rate
        uint256 utilizationRate = newTotalAssets == 0 ? 0 : totalBorrows.mulDiv(1e18, newTotalAssets, Math.Rounding.Up);

        // Supply rate = borrow rate * utilization rate
        return borrowRate.mulDiv(utilizationRate, 1e18);
    }

    /// @notice Calculates the projected SuperPool interest rate if x amount is deposited
    /// @param _superPool Address of the super pool
    /// @param depositAmount The amount to deposit
    /// @return weightedInterestRate The projected weighted interest rate for the SuperPool (in 1e18)
    function projectedSuperPoolRateOnDeposit(
        address _superPool,
        uint256 depositAmount
    )
        external
        view
        returns (uint256 weightedInterestRate)
    {
        SuperPool superPool = SuperPool(_superPool);
        uint256 totalAssets = superPool.totalAssets();
        uint256 newTotalAssets = totalAssets + depositAmount;

        if (newTotalAssets == 0) return 0;

        // Split the function to reduce stack variables
        (uint256[] memory pools, uint256[] memory newPoolAssets) =
            _simulatePoolAssetsAfterDeposit(superPool, depositAmount);

        // Calculate weighted interest rate based on simulated asset distribution
        uint256 poolsLength = pools.length;
        for (uint256 i; i < poolsLength; ++i) {
            uint256 poolId = pools[i];
            uint256 newUtilization = newPoolAssets[i].mulDiv(1e18, newTotalAssets);

            // Calculate how much was deposited into this pool
            uint256 currentAssets = POOL.getAssetsOf(poolId, _superPool);
            uint256 depositedIntoPool = newPoolAssets[i] > currentAssets ? newPoolAssets[i] - currentAssets : 0;

            // Get the projected supply rate for this pool after the deposit
            uint256 supplyRate = depositedIntoPool > 0
                ? projectedSupplyRateOnDeposit(poolId, depositedIntoPool)
                : getPoolSupplyRate(poolId);

            // Add the weighted contribution to the overall rate
            weightedInterestRate += newUtilization.mulDiv(supplyRate, 1e18);
        }
    }

    /// @notice Helper function to simulate pool assets after deposit
    /// @param superPool The super pool
    /// @param depositAmount The amount to deposit
    /// @return pools Array of pool IDs
    /// @return newPoolAssets Array of updated pool assets after deposit
    function _simulatePoolAssetsAfterDeposit(
        SuperPool superPool,
        uint256 depositAmount
    )
        private
        view
        returns (uint256[] memory pools, uint256[] memory newPoolAssets)
    {
        pools = superPool.pools();
        uint256 poolsLength = pools.length;

        // Create a copy of the current assets distribution to simulate changes
        newPoolAssets = new uint256[](poolsLength);
        for (uint256 i; i < poolsLength; ++i) {
            newPoolAssets[i] = POOL.getAssetsOf(pools[i], address(superPool));
        }

        // Simulate sequential deposit following the deposit queue logic
        uint256 remainingDeposit = depositAmount;
        for (uint256 i; i < poolsLength && remainingDeposit > 0; ++i) {
            uint256 poolId = pools[i];
            uint256 poolCap = superPool.poolCapFor(poolId);
            uint256 assetsInPool = newPoolAssets[i];

            // Respect SuperPool cap for this pool
            if (poolCap > assetsInPool) {
                uint256 superPoolCapLeft = poolCap - assetsInPool;
                uint256 depositAmt = remainingDeposit;

                if (superPoolCapLeft < depositAmt) depositAmt = superPoolCapLeft;

                // Also respect base pool cap
                uint256 basePoolCap = POOL.getPoolCapFor(poolId);
                uint256 basePoolTotalAssets = POOL.getTotalAssets(poolId);

                if (basePoolCap > basePoolTotalAssets) {
                    uint256 basePoolCapLeft = basePoolCap - basePoolTotalAssets;
                    if (basePoolCapLeft < depositAmt) depositAmt = basePoolCapLeft;
                } else {
                    depositAmt = 0;
                }

                if (depositAmt > 0) {
                    newPoolAssets[i] += depositAmt;
                    remainingDeposit -= depositAmt;
                }
            }
        }
    }

    function projectedSuperPoolRateOnWithdraw(
        address _superPool,
        uint256 withdrawAmount
    )
        external
        view
        returns (uint256 weightedInterestRate)
    {
        // Get pool information
        SuperPool superPool = SuperPool(_superPool);
        uint256[] memory pools = superPool.pools();
        uint256 newTotalAssets = _calculateNewTotalAssets(_superPool, withdrawAmount);

        if (newTotalAssets == 0) return 0;

        // Get simulated assets distribution after withdrawal
        uint256[] memory newPoolAssets = _simulatePoolAssetsAfterWithdraw(_superPool, withdrawAmount, pools);

        // Calculate weighted interest rate based on simulated asset distribution
        uint256 poolsLength = pools.length;
        for (uint256 i; i < poolsLength; ++i) {
            uint256 poolId = pools[i];
            uint256 newUtilization = newPoolAssets[i].mulDiv(1e18, newTotalAssets);

            // Calculate how much was withdrawn from this pool
            uint256 withdrawnFromPool = POOL.getAssetsOf(poolId, _superPool) > newPoolAssets[i]
                ? POOL.getAssetsOf(poolId, _superPool) - newPoolAssets[i]
                : 0;

            // Get the projected supply rate for this pool after the withdrawal
            uint256 supplyRate = withdrawnFromPool > 0
                ? projectedSupplyRateOnWithdraw(poolId, withdrawnFromPool)
                : getPoolSupplyRate(poolId);

            // Add the weighted contribution to the overall rate
            weightedInterestRate += newUtilization.mulDiv(supplyRate, 1e18);
        }
    }

    /// @notice Helper function to calculate new total assets after withdrawal
    /// @param _superPool Address of the super pool
    /// @param withdrawAmount The amount to withdraw
    /// @return weightedInterestRate The projected weighted interest rate for the SuperPool (in 1e18)
    function _calculateNewTotalAssets(address _superPool, uint256 withdrawAmount) private view returns (uint256) {
        SuperPool superPool = SuperPool(_superPool);
        uint256 totalAssets = superPool.totalAssets();

        // Cap withdrawal to total assets
        uint256 actualWithdraw = withdrawAmount > totalAssets ? totalAssets : withdrawAmount;
        return totalAssets > actualWithdraw ? totalAssets - actualWithdraw : 0;
    }

    /// @notice Helper function to simulate pool assets after withdrawal
    function _simulatePoolAssetsAfterWithdraw(
        address _superPool,
        uint256 withdrawAmount,
        uint256[] memory pools
    )
        private
        view
        returns (uint256[] memory)
    {
        SuperPool superPool = SuperPool(_superPool);
        uint256 totalAssets = superPool.totalAssets();
        uint256 poolsLength = pools.length;

        // Cap withdrawal to total assets and calculate remaining
        uint256 actualWithdraw = withdrawAmount > totalAssets ? totalAssets : withdrawAmount;

        // First check if idle assets are enough to cover the withdrawal
        uint256 idleAssets = IERC20(superPool.asset()).balanceOf(_superPool);
        uint256 remainingWithdraw = idleAssets >= actualWithdraw ? 0 : actualWithdraw - idleAssets;

        // Create a copy of the current assets distribution to simulate changes
        uint256[] memory newPoolAssets = new uint256[](poolsLength);
        for (uint256 i; i < poolsLength; ++i) {
            newPoolAssets[i] = POOL.getAssetsOf(pools[i], _superPool);
        }

        // Simulate sequential withdrawal following withdraw queue logic
        for (uint256 i; i < poolsLength && remainingWithdraw > 0; ++i) {
            // Process one pool at a time
            uint256 poolId = superPool.withdrawQueue(i);
            uint256 withdrawAmt = remainingWithdraw;

            // Find this pool in our array
            uint256 poolIndex = i; // Simplified assumption that withdraw queue order matches pool array order

            // Cap withdrawal amount to what's available in this pool
            withdrawAmt = _min(withdrawAmt, newPoolAssets[poolIndex]);
            withdrawAmt = _min(withdrawAmt, POOL.getLiquidityOf(poolId));

            if (withdrawAmt > 0) {
                newPoolAssets[poolIndex] -= withdrawAmt;
                remainingWithdraw -= withdrawAmt;
            }
        }

        return newPoolAssets;
    }

    /// @notice Helper function to find minimum of two values
    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @notice Fetch current utilization rate for a given pool
    /// @param poolId Id of the underlying pool
    /// @return utilizationRate current utilization rate of the given pool
    function getPoolUtilizationRate(uint256 poolId) public view returns (uint256 utilizationRate) {
        uint256 totalBorrows = POOL.getTotalBorrows(poolId);
        uint256 totalAssets = POOL.getTotalAssets(poolId);
        utilizationRate = totalAssets == 0 ? 0 : totalBorrows.mulDiv(1e18, totalAssets, Math.Rounding.Up);
    }

    /// @notice Fetch current borrow interest rate for a given pool
    /// @param poolId Id of the underlying pool
    /// @return interestRate current borrow interest rate for the given pool
    function getPoolBorrowRate(uint256 poolId) public view returns (uint256 interestRate) {
        IRateModel irm = IRateModel(POOL.getRateModelFor(poolId));
        return irm.getInterestRate(POOL.getTotalBorrows(poolId), POOL.getTotalAssets(poolId));
    }

    /// @notice Fetch current supply interest rate for a given pool
    /// @param poolId Id of the underlying pool
    /// @return interestRate current supply interest rate for the given pool
    function getPoolSupplyRate(uint256 poolId) public view returns (uint256 interestRate) {
        uint256 borrowRate = getPoolBorrowRate(poolId);
        uint256 util = getPoolUtilizationRate(poolId);
        return borrowRate.mulDiv(util, 1e18);
    }
}
