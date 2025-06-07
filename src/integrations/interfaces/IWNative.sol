// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

/// @title IWNative
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Interface for a wrapped native token (WETH9 alike).
interface IWNative {
    /// @notice Deposit ETH to get WETH.
    function deposit() external payable;

    /// @notice Withdraw ETH from WETH.
    /// @param amount The amount to withdraw.
    function withdraw(uint256 amount) external;
}
