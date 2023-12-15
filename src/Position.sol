// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Position {
    // single debt asset
    address public debtAsset;
    address[] public assets;
    mapping(address => uint256) balanceOf;

    function deposit(address asset, bool addAsset, uint256 amt) external {
        if (addAsset) {
            assets.push(asset);
        }
        balanceOf[asset] += amt;
        IERC20(asset).transferFrom(msg.sender, address(this), amt);
    }

    function withdraw(address asset, uint256 amt) external {
        if ((balanceOf[asset] -= amt) == 0) {
            for (uint256 i = 0; i < assets.length; ++i) {
                if (assets[i] == asset) {
                    // TODO remove from array
                }
            }
        }
    }
}
