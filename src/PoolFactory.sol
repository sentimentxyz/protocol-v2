// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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

    function deployPool(PoolDeployParams calldata params) external {
        Pool pool = new Pool(Clones.clone(poolImplementation));
        pool.initialize(params.asset, params.name, params.symbol);
        pool.setRateModel(params.rateModel);
        pool.setOriginationFee(params.originationFee);
        pool.transferOwnership(msg.sender);
        managerFor[pool] = msg.sender;
        // TODO pool created event
    }

    function setPoolImplementation(address _poolImplementation) external onlyOwner {
        poolImplementation = _poolImplementation;
    }
}
