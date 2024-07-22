// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        OracleMock
//////////////////////////////////////////////////////////////*/

import {IOracle} from "src/interfaces/IOracle.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title FixedPriceOracle
/// @notice Oracle implementation for fixed price assets
contract OracleMock is IOracle {
    using Math for uint256;

    address[] assets = new address[](2);
    uint256 public asset1Price;
    uint256 public asset2Price;

    constructor(address[] memory _assets, uint256 _price1, uint256 _price2) {
        asset1Price = _price1;
        asset2Price = _price2;
        for (uint256 i = 0; i < _assets.length; i++) {
            assets[i] = _assets[i];
        }
    }

    function getValueInEth(
        address _asset,
        uint256 amt
    ) external view returns (uint256) {
        // [ROUND] price is rounded down. this is used for both debt and asset math, neutral effect
        // value = amt * price % asset.decimals()
        uint256 price = _asset == assets[0] ? asset1Price : asset2Price;
        return amt.mulDiv(price, (10 ** IERC20Metadata(_asset).decimals()));
    }

    function setAsset1Price(uint256 _price) external {
        asset1Price = _price;
    }

    function randomAsset1Price(uint256 seed) external {
        uint256 newPrice;
        newPrice = bound(
            seed,
            (asset1Price * 9e18) / 10e18,
            (asset1Price * 11e18) / 10e18
        );
        asset1Price = newPrice;
    }

    function setAsset2Price(uint256 _price) external {
        asset2Price = _price;
    }

    function randomAsset2Price(uint256 seed) external {
        uint256 newPrice;
        newPrice = bound(
            seed,
            (asset2Price * 9e18) / 10e18,
            (asset2Price * 11e18) / 10e18
        );
        asset2Price = newPrice;
    }

    function bound(
        uint256 x,
        uint256 min,
        uint256 max
    ) internal pure virtual returns (uint256 result) {
        require(
            min <= max,
            "StdUtils bound(uint256,uint256,uint256): Max is less than min."
        );
        // If x is between min and max, return x directly. This is to ensure that dictionary values
        // do not get shifted if the min is nonzero. More info: https://github.com/foundry-rs/forge-std/issues/188
        if (x >= min && x <= max) return x;

        uint256 size = max - min + 1;

        // If the value is 0, 1, 2, 3, wrap that to min, min+1, min+2, min+3. Similarly for the type(uint256).max side.
        // This helps ensure coverage of the min/max values.
        if (x <= 3 && size > x) return min + x;
        if (x >= type(uint256).max - 3 && size > type(uint256).max - x)
            return max - (type(uint256).max - x);

        // Otherwise, wrap x into the range [min, max], i.e. the range is inclusive.
        if (x > max) {
            uint256 diff = x - max;
            uint256 rem = diff % size;
            if (rem == 0) return max;
            result = min + rem - 1;
        } else if (x < min) {
            uint256 diff = min - x;
            uint256 rem = diff % size;
            if (rem == 0) return min;
            result = max - rem + 1;
        }
    }
}
