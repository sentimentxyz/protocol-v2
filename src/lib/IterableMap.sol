// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// custom impl for an (address => uint256) iterable map
library IterableMap {
    struct IterableMapStorage {
        address[] keys; // list of address keys
        mapping(address => uint256) idxOf; // idxOf[key] = index of key in self.keys + 1
        mapping(address => uint256) valueOf; // mapping of keys to uint256 values
    }

    /// @notice get mapped value for given key
    function get(IterableMapStorage storage self, address key) internal view returns (uint256) {
        return self.valueOf[key];
    }

    /// @notice upsert and remove key-value pairs
    /// @dev setting the value of a key to zero will remove it from the map
    function set(IterableMapStorage storage self, address key, uint256 val) internal returns (uint256) {
        // insert key
        if (self.idxOf[key] == 0) {
            self.keys.push(key);
            self.idxOf[key] = self.keys.length;
        }

        uint256 len = self.keys.length;

        self.valueOf[key] = val;

        if (val == 0) {
            // idx of key to be removed
            uint256 toRemoveIdx = self.idxOf[key] - 1;
            self.idxOf[key] = 0;

            if (toRemoveIdx != len - 1) {
                // copy the last key in self.keys
                address lastKey = self.keys[self.keys.length - 1];

                // overwrite the key to be removed with the last key
                self.keys[toRemoveIdx] = lastKey;

                // update the id of the last key
                self.idxOf[lastKey] = toRemoveIdx + 1;
            }

            self.keys.pop();
        }

        return val;
    }

    /// @notice fetch key by index
    /// @dev queries must be zero-indexed, assume the map is unordered
    function getByIdx(IterableMapStorage storage self, uint256 idx) internal view returns (address) {
        return self.keys[idx];
    }

    /// @notice get all keys
    /// @dev map is unordered
    function getKeys(IterableMapStorage storage self) internal view returns (address[] memory) {
        return self.keys;
    }

    function length(IterableMapStorage storage self) internal view returns (uint256) {
        return self.keys.length;
    }
}
