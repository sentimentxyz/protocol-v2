// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockPrecompile {
    uint256 public price;

    fallback(bytes calldata) external returns (bytes memory) {
        return abi.encode(price);
    }
}
