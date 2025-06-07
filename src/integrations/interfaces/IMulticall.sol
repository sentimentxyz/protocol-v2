// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

/// @title IMulticall
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Interface of Multicall.
interface IMulticall {
    /// @notice Executes an ordered batch of delegatecalls to this contract.
    /// @param data The ordered array of calldata to execute.
    function multicall(bytes[] calldata data) external payable;
}
