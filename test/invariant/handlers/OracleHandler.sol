// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { BeforeAfter } from "../helpers/BeforeAfter.sol";

import { FuzzLibString } from "@fuzzlib/FuzzLibString.sol";
import { Vm } from "forge-std/Test.sol";
import { Pool } from "src/Pool.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract OracleHandler is BeforeAfter {
    function oracle_changePriceAsset1(uint256 seed) public {
        assetOracle.randomAsset1Price(seed);
        assetOracle.randomAsset2Price(seed);
    }

    function oracle_changePriceAsset2(uint256 seed) public {
        assetOracle.randomAsset2Price(seed);
    }
}
