// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { MetaOracle } from "src/oracle/MetaOracle.sol";

contract DeployMetaOracle is BaseScript {
    // Oracle addresses
    address a;
    address b;
    address c;

    // Feed assets
    address feedAssetA;
    address feedAssetB;
    address feedAssetC;

    // Decimals
    uint256 feedDecimalsA;
    uint256 feedDecimalsB;
    uint256 feedDecimalsC;
    uint256 assetDecimals;

    MetaOracle oracle;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new MetaOracle(
            a, b, c, feedAssetA, feedAssetB, feedAssetC, feedDecimalsA, feedDecimalsB, feedDecimalsC, assetDecimals
        );
        console2.log("MetaOracle deployed at: ", address(oracle));
    }

    function getParams() internal {
        a = vm.parseJsonAddress(getConfig(), "$.DeployMetaOracle.a");
        b = vm.parseJsonAddress(getConfig(), "$.DeployMetaOracle.b");
        c = vm.parseJsonAddress(getConfig(), "$.DeployMetaOracle.c");

        feedAssetA = vm.parseJsonAddress(getConfig(), "$.DeployMetaOracle.feedAssetA");
        feedAssetB = vm.parseJsonAddress(getConfig(), "$.DeployMetaOracle.feedAssetB");
        feedAssetC = vm.parseJsonAddress(getConfig(), "$.DeployMetaOracle.feedAssetC");

        feedDecimalsA = vm.parseJsonUint(getConfig(), "$.DeployMetaOracle.feedDecimalsA");
        feedDecimalsB = vm.parseJsonUint(getConfig(), "$.DeployMetaOracle.feedDecimalsB");
        feedDecimalsC = vm.parseJsonUint(getConfig(), "$.DeployMetaOracle.feedDecimalsC");
        assetDecimals = vm.parseJsonUint(getConfig(), "$.DeployMetaOracle.assetDecimals");

        // Log the parameters for verification
        console2.log("Deploying MetaOracle with params:");
        console2.log("Oracle A:", a);
        console2.log("Oracle B:", b);
        console2.log("Oracle C:", c);
        console2.log("Feed Asset A:", feedAssetA);
        console2.log("Feed Asset B:", feedAssetB);
        console2.log("Feed Asset C:", feedAssetC);
        console2.log("Feed Decimals A:", feedDecimalsA);
        console2.log("Feed Decimals B:", feedDecimalsB);
        console2.log("Feed Decimals C:", feedDecimalsC);
        console2.log("Asset Decimals:", assetDecimals);
    }
}
