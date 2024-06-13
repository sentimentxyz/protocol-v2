// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { Pool } from "src/Pool.sol";
import { Position } from "src/Position.sol";
import { PositionManager } from "src/PositionManager.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { PortfolioLens } from "src/lens/PortfolioLens.sol";

contract BaseForkTest is Test {
    string config;
    address sender;
    address usdc;

    Pool pool;
    Position position;
    RiskEngine riskEngine;
    PortfolioLens portfolioLens;
    PositionManager positionManager;

    function setUp() public virtual {
        config = getConfig();
    }

    function getConfig() internal view returns (string memory) {
        string memory path = string.concat(
            vm.projectRoot(), "/config/", vm.toString(block.chainid), "/", vm.envString("FORK_TEST_CONFIG")
        );
        return vm.readFile(path);
    }
}
