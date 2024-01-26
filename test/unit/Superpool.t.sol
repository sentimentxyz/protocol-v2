// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {SuperPool} from "src/SuperPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract SuperPoolTest is Test {
    SuperPool superPool;
    IERC20 mockERC20;

    function setUp() public {
        mockERC20 = IERC20(address(deployMockERC20("Mock token", "MT", 18)));
        superPool = new SuperPool(address(mockERC20), "SuperPool", "SP", address(this));
    }

    function testZereodPoolsAreRemoved() public {
        address pool1 = setDefaultPoolCap();
        address pool2 = setDefaultPoolCap();
        address pool3 = setDefaultPoolCap();

        setPoolCap(pool2, 0);

        address[] memory pools = superPool.pools();

        assertEq(superPool.poolCap(pool2), 0);
        assertEq(address(pools[1]), address(pool3));
        assertEq(address(pools[0]), address(pool1));
        assertEq(superPool.pools().length, 2);
    }

    function testRemoveAllPools() public {
        address pool1 = setDefaultPoolCap();
        address pool2 = setDefaultPoolCap();
        address pool3 = setDefaultPoolCap();

        assertEq(superPool.pools().length, 3);

        setPoolCap(pool1, 0);
        setPoolCap(pool2, 0);
        setPoolCap(pool3, 0);

        assertEq(superPool.pools().length, 0);
    }

    function testPoolCapAdjusted() public {
        address pool1 = setDefaultPoolCap();
        assertEq(superPool.poolCap(pool1), 100);
        assertEq(superPool.totalPoolCap(), 100);
        address pool2 = setDefaultPoolCap();
        assertEq(superPool.poolCap(pool2), 101);
        assertEq(superPool.totalPoolCap(), 201);

        setPoolCap(pool1, 0);

        assertEq(superPool.poolCap(pool1), 0);
        assertEq(superPool.totalPoolCap(), 101);
    }

    function setDefaultPoolCap() public returns (address) {
        uint256 len = superPool.pools().length;
        address pool = deployMockPool();

        superPool.setPoolCap(pool, 100 + len);

        return pool;
    }

    function setPoolCap(address pool, uint256 cap) public {
        superPool.setPoolCap(address(pool), cap);
    }

    function deployMockPool() public returns (address) {
        return address(new MockPool(address(mockERC20)));
    }
}

contract MockPool {
    address public immutable asset;

    constructor(address _asset) {
        asset = _asset;
    }


    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function previewRedeem(uint256) external pure returns (uint256) {
        return 0;
    }
}
