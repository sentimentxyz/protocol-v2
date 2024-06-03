// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Registry
//////////////////////////////////////////////////////////////*/

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Registry
contract Registry is Ownable {
    /// @notice Registry address for a given key hash has been updated
    event AddressSet(bytes32 indexed key, address addr);

    /// @notice Fetch registry address for a given key hash
    mapping(bytes32 key => address addr) public addressFor;

    constructor() Ownable() { }

    /// @notice Update registry address for a given key hash
    /// @param key Registry key hash
    /// @param addr Updated registry address for the key hash
    function setAddress(bytes32 key, address addr) external onlyOwner {
        addressFor[key] = addr;
        emit AddressSet(key, addr);
    }
}
