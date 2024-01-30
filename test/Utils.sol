// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

library TestUtils {
    function makeProxy(address impl, address owner) internal returns (TransparentUpgradeableProxy) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(impl, owner, "");
        return proxy;
    }
}
