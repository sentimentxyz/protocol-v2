// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { HlUsdcOracle } from "src/oracle/HlUsdcOracle.sol";
import { HyperliquidOracle } from "src/oracle/HyperliquidOracle.sol";

contract DeployHyperliquidOracle is BaseScript {
    address public immutable asset = 0x9cf99220F7dA086048D9fd4455407Ca8D65A6588;
    uint256 public immutable assetIndex = 125;
    uint256 public immutable assetAmtScale = 1;
    uint256 public immutable assetPriceScale = 1e12;

    HyperliquidOracle oracle;
    // HlUsdcOracle oracle1;

    function run() public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));

        oracle = new HyperliquidOracle(asset, assetIndex, assetAmtScale, assetPriceScale);
        console2.log("HyperliquidOracle: ", address(oracle));
        uint256 price = oracle.getValueInEth(asset, 1e18);
        console2.log("PURR/ETH: ", price);

        // oracle1 = new HlUsdcOracle();
        // console2.log("UsdcOracle: ", address(oracle1));
        // uint price1 = oracle1.getValueInEth(asset, 1e6);
        // console2.log("USDC/ETH: ", price1);
    }
}
