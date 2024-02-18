// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// libraries
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
// contracts
import {Pool} from "./Pool.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/*//////////////////////////////////////////////////////////////
                            Events
//////////////////////////////////////////////////////////////*/

/// @dev emitted on pool creation
/// @param poolManager msg.sender and pool manager at the time of creation
/// @param pool address to the newly created pool
event PoolCreated(address indexed poolManager, address pool);

/*//////////////////////////////////////////////////////////////
                            Pool Factory
//////////////////////////////////////////////////////////////*/

struct PoolDeployParams {
    address asset;
    address rateModel;
    uint256 poolCap;
    uint256 originationFee;
    string name;
    string symbol;
}

contract PoolFactory is Ownable, Pausable {
    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    // pools are deployed as EIP1167 minimal clones owned by the pool manager (msg.sender)
    /// @notice implementation contract for pool used to create clones
    address public poolImplementation;

    // a mapping can be used to verify that a pool was deployed by this factory
    // storing pool => manager is more useful as a utility mapping than the minimal pool => bool
    /// @notice fetch pool manager for a given pool
    mapping(address pool => address poolManager) public managerFor;

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor(address _poolImplementation) Ownable(msg.sender) {
        poolImplementation = _poolImplementation;
    }

    /*//////////////////////////////////////////////////////////////
                               External
    //////////////////////////////////////////////////////////////*/

    /// @notice deploys a new pool, setting the caller as the owner
    /// @dev the owner can set things like oracles and LTV
    /// @param params the parameters to deploy the pool with
    function deployPool(PoolDeployParams calldata params) external whenNotPaused {
        // deploy pool as a minimal clone
        Pool pool = new Pool(Clones.clone(poolImplementation));

        // init erc4626 params for the pool
        pool.initialize(params.asset, params.name, params.symbol);

        // set interest rate model used by the pool
        pool.setRateModel(params.rateModel);

        // set pool cap
        pool.setPoolCap(params.poolCap);

        // set origination fee for the pool
        pool.setOriginationFee(params.originationFee);

        // transfer pool owner to pool manager - msg.sender
        pool.transferOwnership(msg.sender);

        // store pool manager for given pool
        managerFor[address(pool)] = msg.sender;

        emit PoolCreated(msg.sender, address(pool));
    }

    /*//////////////////////////////////////////////////////////////
                              Only Owner
    //////////////////////////////////////////////////////////////*/

    /// @notice update pool implementation contract used to create clones
    /// @dev only callable by PoolFactory owner
    function setPoolImplementation(address _poolImplementation) external onlyOwner {
        poolImplementation = _poolImplementation;
    }
}
