// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPositionManager {
    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event RiskEngineSet(address riskEngine);

    event PoolFactorySet(address poolFactory);

    event LiquidationFeeSet(uint256 liquidationFee);

    event AddressSet(address indexed target, bool isAllowed);

    event BeaconSet(uint256 indexed positionType, address beacon);

    event AddAsset(uint256 indexed position, address indexed caller, address asset);

    event FunctionSet(address indexed target, bytes4 indexed method, bool isAllowed);

    event RemoveAsset(uint256 indexed position, address indexed caller, address asset);

    event Liquidation(uint256 indexed position, address indexed liquidator, address indexed owner);

    event PositionDeployed(uint256 indexed position, address indexed caller, address indexed owner);

    event Repay(uint256 indexed position, address indexed caller, address indexed pool, uint256 amount);

    event Borrow(uint256 indexed position, address indexed caller, address indexed pool, uint256 amount);

    event Exec(uint256 indexed position, address indexed caller, address indexed target, bytes4 functionSelector);

    event Transfer(uint256 indexed position, address indexed caller, address indexed target, address asset, uint256 amount);

    event Approve(uint256 indexed position, address indexed caller, address indexed spender, address asset, uint256 amount);

    event Deposit(uint256 indexed position, address indexed depositor, address asset, uint256 amount);
}