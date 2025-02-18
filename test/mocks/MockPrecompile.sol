// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockPrecompile {
    mapping (uint16 index => uint64) private _prices;

    function markPx(uint16 index) external view returns (uint64) {
        return _prices[index];
    }

    function setMarkPrice(uint16 index, uint64 price) external {    
        _prices[index] = price;
  }
}
