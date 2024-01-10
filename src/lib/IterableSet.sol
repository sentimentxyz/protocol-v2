// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// custom impl for address iterable map
library IterableSet {
    struct IterableSetStorage {
        address[] elements; // list of set elements
        mapping(address => uint256) idxOf; // idxOf[elem] = index of elem in self.elements + 1
    }

    function insert(IterableSetStorage storage self, address elem) internal {
        if (self.idxOf[elem] != 0) return;
        self.elements.push(elem);
        self.idxOf[elem] = self.elements.length;
    }

    function remove(IterableSetStorage storage self, address elem) internal {
        uint256 idx = self.idxOf[elem];
        if (idx == 0) return;

        // adjust to the actual index
        uint256 toRemoveIdx = idx - 1;
        if (toRemoveIdx != self.elements.length - 1) {
            address lastElem = self.elements[self.elements.length - 1];
            self.elements[toRemoveIdx] = lastElem;
            self.idxOf[lastElem] = toRemoveIdx + 1;
        }
        
        self.idxOf[elem] = 0;
        self.elements.pop();
    }

    function contains(IterableSetStorage storage self, address elem) internal view returns (bool) {
        return (self.idxOf[elem] > 0);
    }

    function getByIdx(IterableSetStorage storage self, uint256 idx) internal view returns (address) {
        return self.elements[idx];
    }

    function getElements(IterableSetStorage storage self) internal view returns (address[] memory) {
        return self.elements;
    }
}
