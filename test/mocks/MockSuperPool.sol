// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SuperPool} from "src/SuperPool.sol";

contract MockSuperPool is SuperPool {
    constructor(
        address pool_,
        address asset_,
        address feeRecipient_,
        uint256 fee_,
        uint256 superPoolCap_,
        string memory name_,
        string memory symbol_
    )
        SuperPool(
            pool_,
            asset_,
            feeRecipient_,
            fee_,
            superPoolCap_,
            name_,
            symbol_
        )
    {}

    function superPoolSimulateAccrue() public view returns (uint256, uint256) {
        return simulateAccrue();
    }
}
