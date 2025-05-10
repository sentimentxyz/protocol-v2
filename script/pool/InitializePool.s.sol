// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "../BaseScript.s.sol";
import { StringUtils } from "../StringUtils.s.sol";
import { console2 } from "forge-std/console2.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { Pool } from "src/Pool.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract InitializePool is BaseScript, StringUtils {
    address pool;
    address owner;
    address asset;
    bytes32 rateModelKey;
    uint256 borrowCap;
    uint256 depositCap;
    uint256 initialDepositAmt;

    function run() public {
        getParams();
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        IERC20(asset).approve(pool, initialDepositAmt);
        uint256 poolId = Pool(pool).initializePool(owner, asset, rateModelKey, depositCap, borrowCap, initialDepositAmt);
        console2.log("poolId: ", poolId);
        vm.stopBroadcast();
    }

    function getParams() internal {
        string memory config = getConfig();
        pool = vm.parseJsonAddress(config, "$.InitializePool.pool");
        owner = vm.parseJsonAddress(config, "$.InitializePool.owner");
        asset = vm.parseJsonAddress(config, "$.InitializePool.asset");
        rateModelKey = vm.parseJsonBytes32(config, "$.InitializePool.rateModelKey");

        // Parse numeric parameters with scientific notation support
        string memory borrowCapStr = vm.parseJsonString(config, "$.InitializePool.borrowCap");
        string memory depositCapStr = vm.parseJsonString(config, "$.InitializePool.depositCap");
        string memory initialDepositStr = vm.parseJsonString(config, "$.InitializePool.initialDepositAmt");

        borrowCap = parseScientificNotation(borrowCapStr);
        depositCap = parseScientificNotation(depositCapStr);
        initialDepositAmt = parseScientificNotation(initialDepositStr);

        console2.log("pool: ", pool);
        console2.log("owner: ", owner);
        console2.log("asset: ", asset);
        console2.log("rateModelKey: ");
        console2.logBytes32(rateModelKey);
        console2.log("borrowCap: ", borrowCap);
        console2.log("depositCap: ", depositCap);
        console2.log("initialDepositAmt: ", initialDepositAmt);
    }
}
