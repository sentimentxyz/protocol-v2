// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IRegistry {
    /// merkle tree here?
    function isSupportedOracle() external view returns (bool);

    function deployPool(
        address asset,
        address[] memory collateralAssets,
        uint256[] memory ltv,
        address[] memory oracle,
        uint256 typeOf
    ) external returns (address);
}