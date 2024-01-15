// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// custom impl for (address => uint256) iterable map
library IterableMapAddress {
    struct IterableMapAddressStorage {
        address[] keys; // list of address keys
        mapping(address => uint256) idxOf; // idxOf[key] = index of key in self.keys + 1
        mapping(address => address) valueOf; // mapping of keys to uint256 values
    }

    function get(IterableMapAddressStorage storage self, address key) internal view returns (address) {
        return self.valueOf[key];
    }

    function remove(IterableMapAddressStorage storage self, address key) internal returns (address) {
        return set(self, key, address(0));
    }

    function set(IterableMapAddressStorage storage self, address key, address val) internal returns (address) {
        // insert key
        if (self.idxOf[key] == 0) {
            self.keys.push(key);
            self.idxOf[key] = self.keys.length;
        }

        uint256 len = self.keys.length;

        self.valueOf[key] = val;

        if (val == address(0)) {
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

    /// @dev zero-indexed key queries
    function getByIdx(IterableMapAddressStorage storage self, uint256 idx) internal view returns (address) {
        return self.keys[idx];
    }

    function getKeys(IterableMapAddressStorage storage self) internal view returns (address[] memory) {
        return self.keys;
    }

    function length(IterableMapAddressStorage storage self) internal view returns (uint256) {
        return self.keys.length;
    }

    function contains(IterableMapAddressStorage storage self, address key) internal view returns (bool) {
        return self.idxOf[key] != 0;
    }
}
