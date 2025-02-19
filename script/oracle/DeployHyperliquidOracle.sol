// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { HyperliquidOracle } from "src/oracle/HyperliquidOracle.sol";

contract DeployHyperliquidOracle is BaseScript {
    address asset;
    uint16 assetIndex;
    uint256 assetAmtScale;
    uint256 assetPriceScale;    

    HyperliquidOracle oracle;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new HyperliquidOracle(asset, assetIndex, assetAmtScale, assetPriceScale);
        console2.log("FixedPriceOracle: ", address(oracle));
    }

    function getParams() internal {
        asset = vm.parseJsonAddress(getConfig(), "$.DeployHyperliquidOracle.asset");
        assetIndex = uint16(vm.parseJsonUint(getConfig(), "$.DeployHyperliquidOracle.assetIndex"));
        assetAmtScale = vm.parseJsonUint(getConfig(), "$.DeployHyperliquidOracle.assetAmtScale");
        assetPriceScale = vm.parseJsonUint(getConfig(), "$.DeployHyperliquidOracle.assetPriceScale");
    }
}
