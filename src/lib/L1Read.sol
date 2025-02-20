// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract L1Read {
  address constant MARK_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000806;

  function markPx(uint16 index) public view returns (uint64) {
    bool success;
    bytes memory result;
    (success, result) = MARK_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(index));
    require(success, "MarkPx precompile call failed");
    return abi.decode(result, (uint64));
  }
}
