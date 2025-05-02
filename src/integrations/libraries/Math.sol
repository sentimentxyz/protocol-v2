// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

/* From morpho-utils Math library */
library Math {
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
