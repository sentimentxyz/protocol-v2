// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            IterableMap
//////////////////////////////////////////////////////////////*/

// custom impl for an (address => uint256) iterable map
library IterableMap {
    /*//////////////////////////////////////////////////////////////
                            Storage Struct
    //////////////////////////////////////////////////////////////*/

    // storage struct for iterable map
    struct IterableMapStorage {
        // list of address keys
        address[] keys;
        // idxOf[key] is the one-indexed location of a particular key in self.keys
        // idxOf[key] = index of key in self.keys + 1
        // idxOf[key] = 0 denotes that key is not present in the map
        mapping(address key => uint256 idxOfKey) idxOf;
        // mapping of keys to uint256 values
        mapping(address key => uint256 value) valueOf;
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice get mapped value for given key
    function get(IterableMapStorage storage self, address key) internal view returns (uint256) {
        return self.valueOf[key];
    }

    /// @notice fetch key by index
    /// @dev zero-indexed queries. map does not preserve order after inserts and deletes
    function getByIdx(IterableMapStorage storage self, uint256 idx) internal view returns (address) {
        return self.keys[idx];
    }

    /// @notice get all keys
    /// @dev map does not preserve order after inserts and deletes
    function getKeys(IterableMapStorage storage self) internal view returns (address[] memory) {
        return self.keys;
    }

    /// @notice fetch the number of elements in the map
    function length(IterableMapStorage storage self) internal view returns (uint256) {
        return self.keys.length;
    }

    /*//////////////////////////////////////////////////////////////
                       State Mutating Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice upsert and remove key-value pairs
    /// @dev setting the value of a key to zero will remove it from the map
    function set(IterableMapStorage storage self, address key, uint256 val) internal returns (uint256) {
        // if given key doesn't exist, insert a new key-value pair
        if (self.idxOf[key] == 0) {
            // push given key to the end of keys array
            self.keys.push(key);

            // update idxOf to reflect that a new key has been added to the map
            self.idxOf[key] = self.keys.length; // idxOf is 1-indexed
        }

        // upsert value for given key-value pair
        self.valueOf[key] = val;

        // val == 0 signals that given key-value pair must be removed
        if (val == 0) {
            // to remove an pair, remove the key from self.keys and update valueOf[key] to zero
            // to remove an key, replace it with the current last element of keys and call pop()

            // fetch idx of key to be removed
            uint256 toRemoveIdx = self.idxOf[key] - 1; // idxOf is 1-indexed

            // fetch number of elements in the map
            uint256 len = self.keys.length;

            // no need to replace keys if the key to be removed is already at the end of self.keys
            if (toRemoveIdx != len - 1) {
                // fetch the current last key in self.keys
                address lastKey = self.keys[len - 1];

                // overwrite the key to be removed with the current last key
                self.keys[toRemoveIdx] = lastKey;

                // update idx of last element to idx of the removed key
                self.idxOf[lastKey] = toRemoveIdx + 1; // idxOf is 1-indexed
            }

            // set idxOf of the removed key to zero
            // idxOf[element] = 0 denotes that key is no longer present in the map
            self.idxOf[key] = 0;

            // pop the keys array to reduce its length by 1 effectively deleting the key to be removed
            self.keys.pop();
        }

        // return the value that was inserted or removed
        return val;
    }
}
