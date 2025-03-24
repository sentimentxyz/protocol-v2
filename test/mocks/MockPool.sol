// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Pool} from "src/Pool.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract MockPool is Pool {
    using Math for uint256;
    function getPoolData(
        uint256 poolId
    ) public view returns (PoolData memory _poolData) {
        _poolData = poolDataFor[poolId];
    }

    function mockSimulateAccrue(uint256 poolId) public view returns (uint256, uint256) {
        PoolData storage _poolData = poolDataFor[poolId];
        return simulateAccrue(_poolData);
    }

    function convertToSharesRounding(
        uint256 assets,
        uint256 totalAssets,
        uint256 totalShares,
        Math.Rounding rounding
    ) public pure returns (uint256) {
        return _convertToShares(
            assets,
            totalAssets,
            totalShares,
            rounding
        );
    }
}
