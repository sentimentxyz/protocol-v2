// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { HlUsdcOracle } from "src/oracle/HlUsdcOracle.sol";
import { HyperliquidOracle } from "src/oracle/HyperliquidOracle.sol";
import { MockPrecompile } from "test/mocks/MockPrecompile.sol";

contract HlOracleTest is Test {
    using Math for uint256;

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

        setMarkPrice(1e6);

        bool success;
        bytes memory result;
        (success, result) = MARK_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(assetIndex));
        console2.log(success);
        console2.logBytes(result);
        console2.log(abi.decode(result, (uint64)));
    }

    function testPerpOracles() public {
        // hlUsdcOracle
        uint256 amt = 1e6;
        uint256 asset_amt_scale = 1e12;

        setMarkPrice(270_000); // 2700.00

        uint256 price = hlUsdcOracle.getValueInEth(asset, amt);
        uint256 expectedPrice = amt * asset_amt_scale / 2700;
        assertEq(expectedPrice, price);

        // hlOracle
        amt = 1e18;
        asset_amt_scale = 1;
        setMarkPrice(2500); // 25.00

        price = hlOracle.getValueInEth(asset, amt);
        expectedPrice = 1e18 * (2500 * 1e12) / uint256(2500 * 1e16);
        assertEq(expectedPrice, price);
    }

    function setMarkPrice(uint256 price) public {
        vm.store(MARK_PX_PRECOMPILE_ADDRESS, bytes32(uint256(0)), bytes32(uint256(price)));
    }
}
