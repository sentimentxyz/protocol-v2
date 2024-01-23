// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// custom impl for an iterable address set
library IterableSet {
    struct IterableSetStorage {
        address[] elements; // list of set elements
        mapping(address => uint256) idxOf; // idxOf[elem] = index of elem in self.elements + 1
    }

    /// @notice add element to set
    /// @dev no-op if element already exists
    function insert(IterableSetStorage storage self, address elem) internal {
        if (self.idxOf[elem] != 0) return;
        self.elements.push(elem);
        self.idxOf[elem] = self.elements.length;
    }

    /// @notice remove element from set
    /// @dev no-op if element does not exist
    function remove(IterableSetStorage storage self, address elem) internal {
        if (self.idxOf[elem] == 0) return;
        uint256 toRemoveIdx = self.idxOf[elem] - 1;
        address lastElem = self.elements[self.elements.length - 1];
        self.elements[toRemoveIdx] = lastElem;
        self.idxOf[lastElem] = toRemoveIdx + 1;
        self.idxOf[elem] = 0;
        self.elements.pop();
    }

    /// @notice check if the set contains a give element
    function contains(IterableSetStorage storage self, address elem) internal view returns (bool) {
        return self.idxOf[elem] > 0;
    }

    /// @notice fetch element by index
    /// @dev set is unordered
    function getByIdx(IterableSetStorage storage self, uint256 idx) internal view returns (address) {
        return self.elements[idx];
    }

    /// @notice fetch all elements in the set
    /// @dev assume set is unordered
    function getElements(IterableSetStorage storage self) internal view returns (address[] memory) {
        return self.elements;
    }
}
