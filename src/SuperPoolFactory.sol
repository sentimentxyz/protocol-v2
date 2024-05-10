// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// contracts
import {SuperPool} from "./SuperPool.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/*//////////////////////////////////////////////////////////////
                        SuperPoolFactory
//////////////////////////////////////////////////////////////*/

contract SuperPoolFactory {
    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    // all superpools from this factory point to a single impl
    address public immutable SUPERPOOL_IMPL;

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event SuperPoolDeployed(address indexed owner, address superPool, string name, string symbol);

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    constructor() {
        // each factory is associated with an immutable superpool impl. initally all instances share
        // the same implementation but they can be upgraded individually, if needed
        SUPERPOOL_IMPL = address(new SuperPool());
    }

    /*//////////////////////////////////////////////////////////////
                          External Functions
    //////////////////////////////////////////////////////////////*/

    function deploy(address owner, SuperPool.SuperPoolInitParams calldata params) external {
        // deploy a new superpool as a transparent proxy pointing to the impl for this factory
        SuperPool superPool =
            SuperPool(address(new TransparentUpgradeableProxy(SUPERPOOL_IMPL, msg.sender, new bytes(0))));

        // init superpool with given params
        superPool.initialize(params);

        // transfer superpool ownership to specified owner
        superPool.transferOwnership(owner);

        // log superpool creation
        emit SuperPoolDeployed(owner, address(superPool), params.name, params.symbol);
    }
}
