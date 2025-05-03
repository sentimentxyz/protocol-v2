// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IStabilityPool
 * @notice Interface for Stability Pool
 * @dev Contains the functions needed for both the wrapper token and the oracle
 */
interface IStabilityPool {
    /**
     * @notice Returns the user's compounded feUSD deposit with earned rewards
     * @param _depositor The address of the depositor
     * @return The compounded feUSD deposit amount
     */
    function getCompoundedfeUSDDeposit(
        address _depositor
    ) external view returns (uint256);

    /**
     * @notice Returns the total feUSD deposits in the stability pool
     * @return The total feUSD deposits
     */
    function getTotalfeUSDDeposits() external view returns (uint256);

    /**
     * @notice Provide feUSD to the Stability Pool
     * @param _amount Amount of feUSD to provide
     * @param _frontEndTag Whether to use front end tag
     */
    function provideToSP(uint256 _amount, bool _frontEndTag) external;
}
