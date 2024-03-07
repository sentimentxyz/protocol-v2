// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SuperPool} from "./SuperPool.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract SuperPoolFactory {
    SuperPool immutable superPoolImpl;

    event SuperPoolInitialized(address indexed owner, address superPool, string name, string symbol);

    constructor() {
        superPoolImpl = new SuperPool();
    }

    function deploy(
        address owner,
        address asset,
        address allocator,
        uint256 protocolFee,
        uint256 totalPoolCap,
        string memory name,
        string memory symbol
    ) external {
        SuperPool superPool =
            SuperPool(address(new TransparentUpgradeableProxy(address(superPoolImpl), msg.sender, new bytes(0))));
        superPool.initialize(asset, totalPoolCap, protocolFee, allocator, name, symbol);
        superPool.transferOwnership(owner);

        emit SuperPoolInitialized(owner, address(superPool), name, symbol);
    }
}
