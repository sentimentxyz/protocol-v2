// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// custom impl for (address => uint256) iterable map
library IterableMap {
    struct IterableMapStorage {
        address[] keys; // list of address keys
        mapping(address => uint256) idxOf; // idxOf[key] = index of key in self.keys + 1
        mapping(address => uint256) valueOf; // mapping of keys to uint256 values
    }

    function get(IterableMapStorage storage self, address key) internal view returns (uint256) {
        return self.valueOf[key];
    }

    function set(IterableMapStorage storage self, address key, uint256 val) internal returns (uint256) {
        // insert key
        if (self.idxOf[key] == 0) {
            self.keys.push(key);
            self.idxOf[key] = self.keys.length;
        }
        self.valueOf[key] = val;
        // remove key
        if (val == 0) {
            address lastKey = self.keys[self.keys.length - 1]; // copy the last key in self.keys
            uint256 toRemoveIdx = self.idxOf[key] - 1; // idx of key to be removed
            self.keys[toRemoveIdx] = lastKey; // overwrite the key to be removed with the last key
            self.idxOf[lastKey] = toRemoveIdx + 1; // update the id of the last key
            self.keys.pop();
        }
        return val;
    }

    /// @dev zero-indexed key queries
    function getByIdx(IterableMapStorage storage self, uint256 idx) internal view returns (address) {
        return self.keys[idx];
    }

    function getKeys(IterableMapStorage storage self) internal view returns (address[] memory) {
        return self.keys;
    }

    function length(IterableMapStorage storage self) internal view returns (uint256) {
        return self.keys.length;
    }
}
