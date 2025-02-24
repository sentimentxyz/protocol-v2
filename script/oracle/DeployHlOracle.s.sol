// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { HlOracle } from "src/oracle/HlOracle.sol";

contract DeployHlOracle is BaseScript {
    address asset;
    uint16 assetIndex;
    uint256 assetAmtScale;
    uint256 assetPriceScale;

    HlOracle oracle;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new HlOracle(asset, assetIndex, assetAmtScale, assetPriceScale);
        console2.log("HlOracle: ", address(oracle));
    }

    function getParams() internal {
        asset = vm.parseJsonAddress(getConfig(), "$.DeployHlOracle.asset");
        assetIndex = uint16(vm.parseJsonUint(getConfig(), "$.DeployHlOracle.assetIndex"));
        assetAmtScale = vm.parseJsonUint(getConfig(), "$.DeployHlOracle.assetAmtScale");
        assetPriceScale = vm.parseJsonUint(getConfig(), "$.DeployHlOracle.assetPriceScale");
    }
}
