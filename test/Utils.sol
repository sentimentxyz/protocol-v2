// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Pool} from "src/Pool.sol";

library TestUtils {
    function makeProxy(address impl, address owner) internal returns (TransparentUpgradeableProxy) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(impl, owner, "");
        return proxy;
    }

    function deployPool(address positionManager, address owner, address asset) internal returns (Pool) {
        Pool pool = new Pool(positionManager);
        pool = Pool(address(makeProxy(address(pool), owner)));
        pool.initialize(asset, "test", "test");
        return pool;
    }
}
