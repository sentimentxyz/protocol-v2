// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Pool } from "../Pool.sol";
import { IRateModel } from "../interfaces/IRateModel.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title RateLens
 * @notice View functions to simulate borrow and supply rates for different scenarios
 * @dev Provides projected rate calculations without actually modifying pool state
 */
contract RateLens {
    using Math for uint256;

    /// @notice Address to the protocol's pool instance
    Pool public immutable POOL;

    /// @param pool Address to the protocol's pool instance
    constructor(address pool) {
        POOL = Pool(pool);
    }

    /**
     * @notice Calculates the projected borrow rate if x amount is borrowed
     * @param poolId Id of the underlying pool
     * @param borrowAmount The amount to borrow
     * @return The projected borrow rate (in 1e18)
     */
    function projectedBorrowRateOnBorrow(uint256 poolId, uint256 borrowAmount) external view returns (uint256) {
        IRateModel irm = IRateModel(POOL.getRateModelFor(poolId));
        
        uint256 totalBorrows = POOL.getTotalBorrows(poolId);
        uint256 totalAssets = POOL.getTotalAssets(poolId);
        
        // Simulate the state after borrowing
        uint256 newBorrows = totalBorrows + borrowAmount;
        
        // Calculate the borrow rate after the hypothetical borrow
        return irm.getInterestRate(newBorrows, totalAssets);
    }
    
    /**
     * @notice Calculates the projected borrow rate if x amount is repaid
     * @param poolId Id of the underlying pool
     * @param repayAmount The amount to repay
     * @return The projected borrow rate (in 1e18)
     */
    function projectedBorrowRateOnRepay(uint256 poolId, uint256 repayAmount) external view returns (uint256) {
        IRateModel irm = IRateModel(POOL.getRateModelFor(poolId));
        
        uint256 totalBorrows = POOL.getTotalBorrows(poolId);
        uint256 totalAssets = POOL.getTotalAssets(poolId);
        
        // Simulate the state after repaying
        uint256 newBorrows = totalBorrows > repayAmount ? totalBorrows - repayAmount : 0;
        
        // Calculate the borrow rate after the hypothetical repay
        return irm.getInterestRate(newBorrows, totalAssets);
    }
    
    /**
     * @notice Calculates the projected supply rate if x amount is deposited
     * @param poolId Id of the underlying pool
     * @param depositAmount The amount to deposit
     * @return The projected supply rate (in 1e18)
     */
    function projectedSupplyRateOnDeposit(uint256 poolId, uint256 depositAmount) external view returns (uint256) {
        IRateModel irm = IRateModel(POOL.getRateModelFor(poolId));
        
        uint256 totalBorrows = POOL.getTotalBorrows(poolId);
        uint256 totalAssets = POOL.getTotalAssets(poolId);
        
        // Simulate the state after depositing
        uint256 newTotalAssets = totalAssets + depositAmount;
        
        // Calculate the borrow rate with the new assets amount
        uint256 borrowRate = irm.getInterestRate(totalBorrows, newTotalAssets);
        
        // Calculate new utilization rate
        uint256 utilizationRate = newTotalAssets == 0 ? 0 : 
                                  totalBorrows.mulDiv(1e18, newTotalAssets, Math.Rounding.Up);
        
        // Supply rate = borrow rate * utilization rate
        return borrowRate.mulDiv(utilizationRate, 1e18);
    }
    
    /**
     * @notice Calculates the projected supply rate if x amount is withdrawn
     * @param poolId Id of the underlying pool
     * @param withdrawAmount The amount to withdraw
     * @return The projected supply rate (in 1e18)
     */
    function projectedSupplyRateOnWithdraw(uint256 poolId, uint256 withdrawAmount) external view returns (uint256) {
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
        uint256 utilizationRate = newTotalAssets == 0 ? 0 : 
                                  totalBorrows.mulDiv(1e18, newTotalAssets, Math.Rounding.Up);
        
        // Supply rate = borrow rate * utilization rate
        return borrowRate.mulDiv(utilizationRate, 1e18);
    }
}
