// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Pool} from "src/Pool.sol";
import {PoolFactory} from "src/PoolFactory.sol";
import {BaseTest} from "./BaseTest.t.sol";
import {PoolDeployParams} from "src/PoolFactory.sol";

contract PoolFactoryTest is BaseTest {
    PoolFactory poolFactory;

    function setUp() public override {
        super.setUp();
        poolFactory = PoolFactory(protocol.poolFactory());
    }

    function testZach_managerNotUpdated() public {
        // deploy a test pool
        Pool pool = Pool(
            poolFactory.deployPool(
                PoolDeployParams({
                    asset: address(0),
                    rateModel: address(0),
                    poolCap: 0,
                    originationFee: 0,
                    name: "test",
                    symbol: "test"
                })
            )
        );

        // manager on the factory is correct
        assert(poolFactory.deployerFor(address(pool)) == pool.owner());

        // after transferring ownership, factory isn't updated
        pool.transferOwnership(address(1));
        assert(poolFactory.deployerFor(address(pool)) != pool.owner());
    }
}
