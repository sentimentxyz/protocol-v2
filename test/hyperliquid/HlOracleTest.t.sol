// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { HlUsdcOracle } from "src/oracle/HlUsdcOracle.sol";
import { HyperliquidOracle } from "src/oracle/HyperliquidOracle.sol";
import { MockPrecompile } from "test/mocks/MockPrecompile.sol";

contract HlOracleTest is Test {
    HlUsdcOracle hlUsdcOracle;
    HyperliquidOracle hlOracle;

    address public immutable MARK_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000806;

    uint16 public immutable ethIndex = 4;

    address public immutable asset = 0x9cf99220F7dA086048D9fd4455407Ca8D65A6588;
    uint16 public immutable assetIndex = 1035; // HYPE index
    uint256 public immutable assetAmtScale = 1;
    uint256 public immutable assetPriceScale = 1e12;

    function setUp() public {
        hlUsdcOracle = new HlUsdcOracle();
        hlOracle = new HyperliquidOracle(asset, assetIndex, assetAmtScale, assetPriceScale);

        MockPrecompile mockPrecompile = new MockPrecompile();

        vm.etch(MARK_PX_PRECOMPILE_ADDRESS, address(mockPrecompile).code);

        // set mark price
        vm.store(MARK_PX_PRECOMPILE_ADDRESS, bytes32(uint256(0)), bytes32(uint256(275380)));

        bool success;
        bytes memory result;
        (success, result) = MARK_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(assetIndex));
        console2.log(success);
        console2.logBytes(result);
        console2.log(abi.decode(result, (uint64)));
    }

    function testPerpOracles() public view {
        uint256 usdcPrice = hlUsdcOracle.getValueInEth(asset, 1e6);
        uint256 assetPrice = hlOracle.getValueInEth(asset, 1e18);
        console2.log("usdcPrice: ", usdcPrice);
        console2.log("assetPrice: ", assetPrice);
    }

    // TODO
    function testDecimals() public view {}
}
