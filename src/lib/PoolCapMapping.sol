// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

library PoolCapMapping {
    struct PoolCapMappingStorage {
        /// List of pools
        IERC4626[] pools;
        /// The pool cap
        mapping(IERC4626 => uint256) poolCap;
        /// Actually stores poolIdx + 1
        mapping(IERC4626 => uint256) poolIdx;
    }

    event PoolCapSet(address indexed pool, uint256 amt);
    event PoolDeposit(address indexed pool, uint256 assets);
    event PoolWithdraw(address indexed pool, uint256 assets);

    function set(PoolCapMappingStorage storage self, IERC4626 _pool, uint256 assets) internal {
        // check that weve seen this pool before
        if (self.poolIdx[_pool] == 0) {
            self.pools.push(_pool);

            self.poolIdx[_pool] = self.pools.length;
        }

        self.poolCap[_pool] = assets;

        // remove the pool if we set the cap to 0
        if (assets == 0) {
            uint256 len = self.pools.length;
            
            // get the actual index of the pool
            uint256 toRemoveIdx = poolIdx(self, _pool);

            if (toRemoveIdx == len - 1) {
                // If the pool is the last element in the list, just set its index to 0 and pop
                // Handles 1 case also
                self.poolIdx[_pool] = 0;
            } else {
                // copy the last pool address so we can adjust its index 
                IERC4626 lastPool = self.pools[len - 1];


                // Repalce the pool to remove with the last pool
                self.pools[toRemoveIdx] = lastPool;


                // adjust the index of the pool we just moved
                self.poolIdx[lastPool] = toRemoveIdx + 1;
            }

            self.pools.pop();
        }
    }

    function read(PoolCapMappingStorage storage self, IERC4626 _pool) internal view returns (uint256) {
        return self.poolCap[_pool];
    }

    function pool(PoolCapMappingStorage storage self, uint256 idx) internal view returns (IERC4626) {
        return self.pools[idx];
    }

    function allPools(PoolCapMappingStorage storage self) internal view returns (IERC4626[] memory) {
        return self.pools;
    }

    function length(PoolCapMappingStorage storage self) internal view returns (uint256) {
        return self.pools.length;
    }

    /// @notice Returns the actual index of the pool
    function poolIdx(PoolCapMappingStorage storage self, IERC4626 _pool) private view returns (uint256) {
        return self.poolIdx[_pool] - 1;
    }
} 