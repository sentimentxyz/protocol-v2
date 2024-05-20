// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// contracts
import {SuperPool} from "./SuperPool.sol";

/*//////////////////////////////////////////////////////////////
                        SuperPoolFactory
//////////////////////////////////////////////////////////////*/

contract SuperPoolFactory {
    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/
    // all superpools from this factory point to a single impl
    address public immutable POOL;

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event SuperPoolDeployed(address indexed owner, address superPool, string name, string symbol);

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address _pool) {
        // each factory is associated with an immutable superpool impl. initally all instances share
        // the same implementation but they can be upgraded individually, if needed
        POOL = _pool;
    }

    /*//////////////////////////////////////////////////////////////
                          External Functions
    //////////////////////////////////////////////////////////////*/

    function deploy(
        address owner,
        address asset,
        address feeRecipient,
        uint256 fee,
        uint256 superPoolCap,
        string calldata name,
        string calldata symbol
    ) external returns (address) {
        // deploy a new superpool as a transparent proxy pointing to the impl for this factory
        SuperPool superPool = new SuperPool(POOL, asset, feeRecipient, fee, superPoolCap, name, symbol);

        // transfer superpool ownership to specified owner
        superPool.transferOwnership(owner);

        // log superpool creation
        emit SuperPoolDeployed(owner, address(superPool), params.name, params.symbol);

        return address(superPool);
    }
}
