// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import {PortfolioLens} from "src/lens/PortfolioLens.sol";
import {SuperPoolLens} from "src/lens/SuperPoolLens.sol";

contract DeployLens is BaseScript {
    address pool;
    address positionManager;
    PortfolioLens portfolioLens;
    SuperPoolLens superPoolLens;

    function run() public {
        getParams();

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        portfolioLens = new PortfolioLens(pool, positionManager);
        superPoolLens = new SuperPoolLens(pool);
        vm.stopBroadcast();
    }

    function getParams() internal {
        string memory config = getConfig();

        pool = vm.parseJsonAddress(config, "$.DeployLens.pool");
        positionManager = vm.parseJsonAddress(config, "$.DeployLens.positionManager");
    }
}
