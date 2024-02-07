// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// custom impl for an iterable address set
library IterableSet {
    /*//////////////////////////////////////////////////////////////
                            Storage Struct
    //////////////////////////////////////////////////////////////*/

    // storage struct for iterable set
    struct IterableSetStorage {
        // list of elements in the set
        address[] elements;
        // idxOf[element] is the one-indexed location of a particular element in self.elements
        // idxOf[element] = index of key in self.elements + 1
        // idxOf[element] = 0 denotes that element is not present in the map
        mapping(address => uint256) idxOf;
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice check if the set contains a give element
    function contains(IterableSetStorage storage self, address elem) internal view returns (bool) {
        // since idxOf[element] = 0 denotes that element is not present in the map
        // any other value implies that the element is in the set
        return self.idxOf[elem] > 0;
    }

    /// @notice fetch element by index
    /// @dev zero-indexed queries. set does not preserve order after inserts and removals
    function getByIdx(IterableSetStorage storage self, uint256 idx) internal view returns (address) {
        return self.elements[idx];
    }

    /// @notice fetch all elements in the set
    /// @dev set does not preserve order after inserts and deletes
    function getElements(IterableSetStorage storage self) internal view returns (address[] memory) {
        return self.elements;
    }

    /// @notice fetch the number of elements in the set
    function length(IterableSetStorage storage self) internal view returns (uint256) {
        return self.elements.length;
    }

    /*//////////////////////////////////////////////////////////////
                       State Mutating Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice add element to set
    /// @dev no-op if element already exists
    function insert(IterableSetStorage storage self, address elem) internal {
        // return silently if element is already in the set
        if (self.idxOf[elem] != 0) return;

        // push elem to the end of self.elements
        self.elements.push(elem);

        // update idx of elem in the index mapping
        self.idxOf[elem] = self.elements.length;
    }

    /// @notice remove element from set
    /// @dev no-op if element does not exist
    function remove(IterableSetStorage storage self, address elem) internal {
        // return silently if the elem is not in the set
        if (self.idxOf[elem] == 0) return;

        // to remove an element, replace it with the current last element, update idxOf and call pop()
        // if the element to be removed is the last element, simply update idxOf and call pop()

        // idx of element to be removed
        uint256 toRemoveIdx = self.idxOf[elem] - 1;

        // fetch number of elements in set
        uint256 len = self.elements.length;

        // no need to replace elements if the element to be removed is already at the end
        if (toRemoveIdx != len - 1) {
            // fetch value of current last element
            address lastElem = self.elements[len - 1];

            // overwrite the element to be removed with the last element
            self.elements[toRemoveIdx] = lastElem;

            // update idx of last element to idx of the removed element
            self.idxOf[lastElem] = toRemoveIdx + 1; // idxOf mapping is 1-indexed
        }

        // set idxOf of the removed element to zero
        // idxOf[element] = 0 denotes that element is not present in the map anymore
        self.idxOf[elem] = 0;

        // pop the elements array to reduce its length by 1 effectively deleting elem
        self.elements.pop();
    }
}
