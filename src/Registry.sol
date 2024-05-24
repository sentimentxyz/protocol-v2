// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract Registry is Ownable {
    event AddressSet(bytes32 indexed key, address addr);

    mapping(bytes32 key => address addr) public addressFor;

    constructor() Ownable(msg.sender) { }

    function setAddress(bytes32 key, address addr) external onlyOwner {
        addressFor[key] = addr;

        emit AddressSet(key, addr);
    }
}
