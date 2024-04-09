// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {IOracle} from "../interface/IOracle.sol";

contract ZeroOracle is IOracle {
    function getValueInEth(address, uint256) external pure returns (uint256) {
        return 0;
    }
}
