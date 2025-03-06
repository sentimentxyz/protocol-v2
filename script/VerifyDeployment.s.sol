// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "./BaseScript.s.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Pool } from "src/Pool.sol";
import { SuperPool } from "src/SuperPool.sol";
import { Position } from "src/Position.sol";
import { PositionManager } from "src/PositionManager.sol";
import { Registry } from "src/Registry.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { RiskModule } from "src/RiskModule.sol";
import { SuperPoolFactory } from "src/SuperPoolFactory.sol";
import { PortfolioLens } from "src/lens/PortfolioLens.sol";
import { SuperPoolLens } from "src/lens/SuperPoolLens.sol";
import { AggV3Oracle } from "src/oracle/AggV3Oracle.sol";

contract VerifyDeployment is BaseScript {
    // registry
    Registry public registry;
    // superpool factory
    SuperPoolFactory public superPoolFactory;
    // position manager
    address positionManagerImpl;
    PositionManager public positionManager;
    // risk
    RiskEngine public riskEngine;
    RiskModule public riskModule;
    // pool
    address poolImpl;
    Pool public pool;
    // superPool
    SuperPool public superPool;
    // position
    address public positionBeacon;
    // lens
    SuperPoolLens public superPoolLens;
    PortfolioLens public portfolioLens;
    // oracles
    AggV3Oracle public oracle1;
    AggV3Oracle public oracle2;

    uint public poolId;

    // keccak(SENTIMENT_POSITION_MANAGER_KEY)
    bytes32 public constant SENTIMENT_POSITION_MANAGER_KEY =
        0xd4927490fbcbcafca716cca8e8c8b7d19cda785679d224b14f15ce2a9a93e148;
    // keccak(SENTIMENT_POOL_KEY)
    bytes32 public constant SENTIMENT_POOL_KEY = 0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728;
    // keccak(SENTIMENT_RISK_ENGINE_KEY)
    bytes32 public constant SENTIMENT_RISK_ENGINE_KEY =
        0x5b6696788621a5d6b5e3b02a69896b9dd824ebf1631584f038a393c29b6d7555;
    // keccak(SENIMENT_POSITION_BEACON_KEY)
    bytes32 public constant SENTIMENT_POSITION_BEACON_KEY =
        0x6e7384c78b0e09fb848f35d00a7b14fc1ad10ae9b10117368146c0e09b6f2fa2;
    // keccak(SENTIMENT_RISK_MODULE_KEY)
    bytes32 public constant SENTIMENT_RISK_MODULE_KEY =
        0x881469d14b8443f6c918bdd0a641e9d7cae2592dc28a4f922a2c4d7ca3d19c77;

    // Assets
    address public constant mockwHYPE = 0xB3fB66C10fD75E7ceB7E491d8dF505De0d91d340;
    address public constant mockUSDC = 0xdeC702aa5a18129Bd410961215674A7A130A12e5;
    address public constant wHYPE = 0x5555555555555555555555555555555555555555;
    address public constant wstHYPE = 0x94e8396e0869c9F2200760aF0621aFd240E1CF38;

    function run() public { 
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        _run();
    }

    function _run() internal {
        // SuperPool
        superPool = SuperPool(0xF9BFAbBEa21170905A94399B8Cab724009B0639c);
        console2.log("superpool: ", superPool.name());
        console2.log("asset: ", superPool.asset());
        console2.log("owner: ", superPool.owner());
        poolId = superPool.pools()[0];
        console2.log("pool id: ", poolId);
        console2.log("fee: ", superPool.fee());
        console2.log("fee recipient: ", superPool.feeRecipient());
        console2.log("superPoolCap: ", superPool.superPoolCap());

        // Pool
        pool = Pool(0xCF5e73C836f40fA83ED634259978F9c3A3FC26f8);
        console2.log("pool: ");
        console2.log("proxy owner: ", pool.owner());
        console2.log("pool owner: ", pool.ownerOf(poolId));
        console2.log("fee recipient: ", pool.feeRecipient());
        console2.log("positionManager: ", pool.positionManager());
        console2.log("riskEngine: ", pool.riskEngine());
        console2.log("pool asset: ", pool.getPoolAssetFor(poolId));
        console2.log("pool rateModel: ", pool.getRateModelFor(poolId));
        console2.log("poolCap: ", pool.getPoolCapFor(poolId));
        console2.log("borrowCap: ", pool.getBorrowCapFor(poolId));

        // Oracles
        oracle1 = AggV3Oracle(0x88d7c82a326C8149718a191AfB035D5c2eDa35D1);
        oracle2 = AggV3Oracle(0x6231FDcEaa9480841Cef8F95093b8869BbE8723A);
        console2.log("oracle1 price: ", oracle1.getValueInEth(mockwHYPE, 1e18));
        console2.log("oracle2 price: ", oracle2.getValueInEth(mockUSDC, 1e6));
    }
}
