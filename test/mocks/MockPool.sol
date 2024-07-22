// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Pool} from "src/Pool.sol";

contract MockPool is Pool {
    function getPoolData(
        uint256 poolId
    ) public view returns (PoolData memory _poolData) {
        _poolData = poolDataFor[poolId];
    }

    function mockSimulateAccrue(uint256 poolId) public view returns (uint256, uint256) {
        PoolData storage _poolData = poolDataFor[poolId];
        return simulateAccrue(_poolData);
    }
}
