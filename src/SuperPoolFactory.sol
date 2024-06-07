// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        SuperPoolFactory
//////////////////////////////////////////////////////////////*/

import { SuperPool } from "./SuperPool.sol";

/// @title SuperPoolFactory
/// @notice Factory for creating SuperPools, which act as aggregators over individual pools
/// @dev A new factory must be deployed if the SuperPool implementation is upgraded
contract SuperPoolFactory {
    /// @notice All Pools exist on the Singleton Pool Contract, which is fixed per factory
    address public immutable POOL;

    /// @notice New Super Pool instance was deployed
    event SuperPoolDeployed(address indexed owner, address superPool, string name, string symbol);

    /// @param _pool The address of the pool contract
    constructor(address _pool) {
        POOL = _pool;
    }

    // SuperPool deployment flow:
    // 1. Deploy a new superpool as a transparent proxy using the factory impl
    // 2. Transfer superpool ownership to the specified owner
    // 3. Emit SuperPool creation log
    // 4. Return the address to the newly deployed SuperPool

    /// @notice Deploy a new SuperPool
    /// @param owner Owner of the SuperPool, and tasked with allocation and adjusting Pool Caps
    /// @param asset The asset to be deposited in the SuperPool
    /// @param feeRecipient The address to initially receive the fee
    /// @param fee The fee, out of 1e18, taken from interest earned
    /// @param superPoolCap The maximum amount of assets that can be deposited in the SuperPool
    /// @param name The name of the SuperPool
    /// @param symbol The symbol of the SuperPool
    function deploySuperPool(
        address owner,
        address asset,
        address feeRecipient,
        uint256 fee,
        uint256 superPoolCap,
        string calldata name,
        string calldata symbol
    ) external returns (address) {
        SuperPool superPool = new SuperPool(POOL, asset, feeRecipient, fee, superPoolCap, name, symbol);
        superPool.transferOwnership(owner);
        emit SuperPoolDeployed(owner, address(superPool), name, symbol);
        return address(superPool);
    }
}
