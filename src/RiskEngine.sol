// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IRiskManager} from "src/interfaces/IRiskManager.sol";
import {RiskEngineBase} from "src/risk/RiskEngineBase.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPosition} from "src/interfaces/IPosition.sol";

contract RiskEngine is RiskEngineBase, Ownable {
    error Unauthorized();
    error InvalidLTV();
    error InvalidOracle();

    mapping(address => address) poolManager;
    mapping (uint256 => address impl) public implementations;

    constructor(address _owner) Ownable(_owner) {}

    address public registry;

    modifier onlyPoolManager(address pool) {
        if (poolManager[pool] != msg.sender) revert Unauthorized();
        _;
    }

    function setImplementation(uint256 id, address _impl) external onlyOwner {
        implementations[id] = _impl;
    }
    
    function isPositionHealthy(
        address position
    ) external view override returns (bool success) {
        IPosition _position = IPosition(position);
        address impl = implementations[_position.TYPE()];

        assembly {
            if iszero(mload(impl)) {
                revert(0, 0)
            }
            // should fit in scratch space 
            calldatacopy(0, 0, calldatasize())
            success := delegatecall(gas(), mload(impl), 0, calldatasize(), 0, 0)
            if iszero(success) {
                revert(0, 0)
            }
        }
    }

    // todo only registry?
    // function setOracle(address pool, address asset, address _oracle, uint256 _ltv) external onlyPoolManager(pool) {
    //     if (_ltv > 10000 || _ltv == 0) revert InvalidLTV();
    //     if (_oracle == address(0)) revert InvalidOracle();

    //     oracles[pool].set(asset, _oracle);
    //     ltv[pool][asset] = _ltv;
    // }

    // function removeOracle(address pool, address asset) external onlyPoolManager(pool) {
    //     oracle.remove(asset);
    //     loanToValueBP[asset] = 0;
    // }
}