// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IterableMap} from "src/lib/IterableMap.sol";
import {IterableSet} from "src/lib/IterableSet.sol";
import {Test, console2} from "forge-std/Test.sol";

contract IterableTest is Test {
    IterableSet.IterableSetStorage set;
    IterableMap.IterableMapStorage map;

    using IterableSet for IterableSet.IterableSetStorage;
    using IterableMap for IterableMap.IterableMapStorage;

    mapping(address => bool) included;

    function testFuzzIterableSet(address[] memory els, bool unique) public {
        if (unique) els = _uniquify(els);

        for (uint256 i = 0; i < els.length; i++) {
            set.insert(els[i]);
        }
        for (uint256 i = 0; i < els.length; i++) {
            assertTrue(set.contains(els[i]));
        }
        if (unique) {
            assert(set.length() == els.length);
            assert(keccak256(abi.encode(set.getElements())) == keccak256(abi.encode(els)));
        }

        for (uint256 i = 0; i < els.length; i++) {
            set.remove(els[i]);
        }
        for (uint256 i = 0; i < els.length; i++) {
            assertFalse(set.contains(els[i]));
        }

        assert(set.length() == 0);
    }

    function testFuzzIterableMap(address[] memory ks, uint256[] memory vs) public {
        ks = _uniquify(ks);

        if (ks.length > vs.length) {
            assembly {
                mstore(ks, mload(vs))
            }
        } else {
            assembly {
                mstore(vs, mload(ks))
            }
        }

        uint256 count;
        address[] memory nonZeroKs = new address[](ks.length);
        for (uint256 i = 0; i < ks.length; i++) {
            map.set(ks[i], vs[i]);
            if (vs[i] != 0) {
                nonZeroKs[count] = ks[i];
                count++;
            }
        }
        assembly {
            mstore(nonZeroKs, count)
        }

        assert(map.length() == count);
        assertEq(keccak256(abi.encode(map.getKeys())), keccak256(abi.encode(nonZeroKs)));

        for (uint256 i = 0; i < ks.length; i++) {
            assert(map.get(ks[i]) == vs[i]);
        }
    }

    function testIterableMapSetChangeUnset() public {
        map.set(address(1), 1);
        assertEq(map.getByIdx(0), address(1));
        assertEq(map.get(address(1)), 1);
        assertEq(map.length(), 1);

        map.set(address(1), 2);
        assertEq(map.getByIdx(0), address(1));
        assertEq(map.get(address(1)), 2);
        assertEq(map.length(), 1);

        map.set(address(1), 0);
        vm.expectRevert();
        map.getByIdx(0);
        assertEq(map.get(address(1)), 0);
        assertEq(map.length(), 0);
    }

    function testFuzzIterableMapNewZeroIsNoop(address[] memory ks, uint256[] memory vs, address addition) public {
        ks = _uniquify(ks);

        if (ks.length > vs.length) {
            assembly {
                mstore(ks, mload(vs))
            }
        } else {
            assembly {
                mstore(vs, mload(ks))
            }
        }

        for (uint256 i = 0; i < ks.length; i++) {
            map.set(ks[i], vs[i]);
        }

        vm.assume(map.get(addition) == 0);
        bytes32 startingHash = keccak256(abi.encode(map.keys));
        map.set(addition, 0);
        assertEq(startingHash, keccak256(abi.encode(map.keys)));
    }

    function _uniquify(address[] memory els) internal returns (address[] memory) {
        address[] memory unique_els = new address[](els.length);
        uint256 counter = 0;
        for (uint256 i = 0; i < els.length; i++) {
            if (included[els[i]]) {
                continue;
            }
            unique_els[counter] = els[i];
            included[els[i]] = true;
            counter++;
        }
        assembly {
            mstore(unique_els, counter)
        }
        return unique_els;
    }
}
