// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IOracle} from "src/interfaces/IOracle.sol";
import {IterableMapAddress} from "src/lib/IterableMapAddress.sol";

interface ILoanManager is IOracle {
    function setOracle(address asset, IOracle _oracle) external;
    function oracleFor(address asset) external view returns (IOracle);
    function supportedTokens() external view returns (address[] memory);
    function ltv(address asset) external view returns (uint256);
}