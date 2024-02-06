// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// libraries
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
// contracts
import {Pool} from "./Pool.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PoolFactory is Ownable {
    address public poolImplementation;
    mapping(address pool => address poolManager) public managerFor;

    constructor(address _poolImplementation) Ownable(msg.sender) {
        poolImplementation = _poolImplementation;
    }

    struct PoolDeployParams {
        address asset;
        address rateModel;
        uint256 originationFee;
        string name;
        string symbol;
    }

    /// @notice deploys a new pool, setting the caller as the owner
    /// @dev the owner can set things like oracles and LTV
    /// @param params the parameters to deploy the pool with
    function deployPool(PoolDeployParams calldata params) external {
        Pool pool = new Pool(Clones.clone(poolImplementation));
        pool.initialize(params.asset, params.name, params.symbol);
        pool.setRateModel(params.rateModel);
        pool.setOriginationFee(params.originationFee);
        pool.transferOwnership(msg.sender);
        managerFor[address(pool)] = msg.sender;
        // TODO pool created event
    }

    function setPoolImplementation(address _poolImplementation) external onlyOwner {
        poolImplementation = _poolImplementation;
    }
}
