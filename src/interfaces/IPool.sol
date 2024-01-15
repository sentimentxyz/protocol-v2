// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IOracle} from "src/interfaces/IOracle.sol";
import {ILoanManager} from "src/interfaces/ILoanManager.sol";

interface IPool is ILoanManager {
    // Pool functions
    function asset() external view returns (address);
    function borrow(address position, uint256 amt) external;
    function getBorrowsOf(address position) external view returns (uint256);
    function repay(address position, uint256 amt) external returns (uint256);
}
