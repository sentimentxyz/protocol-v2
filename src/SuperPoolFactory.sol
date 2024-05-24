// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// contracts
import { SuperPool } from "./SuperPool.sol";

/// @title SuperPoolFactory
/// @notice Factory for creating SuperPools, which act as aggregators over individual pools
contract SuperPoolFactory {
    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    /// @notice All Pools exist on the Singleton Pool Contract, which is fixed per factory
    address public immutable POOL;

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @notice An event for indexing the creation of a new superpool
    /// @custom:field owner - The owner of the superpool
    /// @custom:field superPool - The address of the superpool
    /// @custom:field name - The name of the superpool
    /// @custom:field symbol - The symbol of the superpool
    event SuperPoolDeployed(address indexed owner, address superPool, string name, string symbol);

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructor for the SuperPoolFactory
    /// @param _pool The address of the pool contract
    constructor(address _pool) {
        POOL = _pool;
    }

    /*//////////////////////////////////////////////////////////////
                          External Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy a new SuperPool
    /// @param owner Owner of the SuperPool, and tasked with allocation and adjusting Pool Caps
    /// @param asset The asset to be deposited in the SuperPool
    /// @param feeRecipient The address to initially receive the fee
    /// @param fee The fee, out of 1e18, taken from interest earned
    /// @param superPoolCap The maximum amount of assets that can be deposited in the SuperPool
    /// @param name The name of the SuperPool
    /// @param symbol The symbol of the SuperPool
    ///
    /// @return newPool The address of the newly deployed SuperPool
    function deploy(
        address owner,
        address asset,
        address feeRecipient,
        uint256 fee,
        uint256 superPoolCap,
        string calldata name,
        string calldata symbol
    )
        external
        returns (address newPool)
    {
        // deploy a new superpool as a transparent proxy pointing to the impl for this factory
        SuperPool superPool = new SuperPool(POOL, asset, feeRecipient, fee, superPoolCap, name, symbol);

        // transfer superpool ownership to specified owner
        superPool.transferOwnership(owner);

        // log superpool creation
        emit SuperPoolDeployed(owner, address(superPool), name, symbol);

        return address(superPool);
    }
}
