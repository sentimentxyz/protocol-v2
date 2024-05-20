// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Owned } from "lib/solmate/src/auth/Owned.sol";

contract Registry is Owned(msg.sender) {
    event AddressSet(bytes32 indexed key, address addr);

    mapping(bytes32 key => address addr) public addressFor;

    function setAddress(bytes32 key, address addr) external onlyOwner {
        addressFor[key] = addr;

        emit AddressSet(key, addr);
    }
}
