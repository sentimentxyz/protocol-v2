// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "./BaseScript.s.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { Pool } from "src/Pool.sol";

import { Position } from "src/Position.sol";
import { PositionManager } from "src/PositionManager.sol";

import { Action, Operation, PositionManager } from "src/PositionManager.sol";
import { Registry } from "src/Registry.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { RiskModule } from "src/RiskModule.sol";
import { SuperPool } from "src/SuperPool.sol";
import { SuperPoolFactory } from "src/SuperPoolFactory.sol";
import { PortfolioLens } from "src/lens/PortfolioLens.sol";
import { SuperPoolLens } from "src/lens/SuperPoolLens.sol";
import { AggV3Oracle } from "src/oracle/AggV3Oracle.sol";
import { ActionUtils } from "test/utils/ActionUtils.sol";

contract VerifyDeployment is BaseScript {
    using ActionUtils for Action;

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

    uint256 public poolId;

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
    address public constant borrowAsset = 0x5555555555555555555555555555555555555555; // wHype
    address public constant collateralAsset = 0x94e8396e0869c9F2200760aF0621aFd240E1CF38; // wstHype

    bytes32 constant SALT = "INITIAL_TEST_SALT";

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // Set live contract addresses
        superPool = SuperPool(0x17D9bA6c4276A5A679221B7128Ad3301d2b857B1);
        pool = Pool(0xE5B81a2bdaE122EE8E538CF866d721F09539556F);
        riskEngine = RiskEngine(0x5f7e170Be9ac684fF221b55B956d95b10eaBA3C8);
        portfolioLens = PortfolioLens(0xF3487f4731f63B9AD94aAEa1F8A97a38Ec64c2E9);
        positionManager = PositionManager(0xE709523Bf6902b757B1A741187b5c10F2e24e463);

        oracle1 = AggV3Oracle(0x79479c3d10b7fF49D6c18A5ADC601c86472D4767);
        oracle2 = AggV3Oracle(0x712047cC3e4b0023Fccc09Ae412648CF23C65ed3);

        _run();
    }

    function _run() internal {
        // SuperPool
        console2.log("superpool: ", superPool.name());
        console2.log("asset: ", superPool.asset());
        console2.log("owner: ", superPool.owner());
        poolId = superPool.pools()[0];
        console2.log("pool id: ", poolId);
        console2.log("fee: ", superPool.fee());
        console2.log("fee recipient: ", superPool.feeRecipient());
        console2.log("superPoolCap: ", superPool.superPoolCap());

        // Pool
        console2.log("pool: ");
        console2.log("proxy owner: ", pool.owner());
        console2.log("pool owner: ", pool.ownerOf(poolId));
        console2.log("fee recipient: ", pool.feeRecipient());
        console2.log("positionManager: ", pool.positionManager());
        console2.log("riskEngine: ", pool.riskEngine());
        console2.log("pool asset: ", pool.getPoolAssetFor(poolId));
        console2.log("pool rateModel: ", pool.getRateModelFor(poolId));
        console2.log("poolCap: ", pool.getPoolCapFor(poolId));
        console2.log("pool borrowCap: ", pool.getBorrowCapFor(poolId));
        console2.log("pool minDebt: ", pool.minDebt());
        console2.log("pool minBorrow: ", pool.minBorrow());

        //RiskEngine
        console2.log("RiskEngine: ", address(riskEngine));
        console2.log("collateralAsset ltv: ", riskEngine.ltvFor(poolId, collateralAsset));
        console2.log("borrowAsset ltv: ", riskEngine.ltvFor(poolId, borrowAsset));

        // Oracles
        console2.log("collateralAsset price: ", oracle1.getValueInEth(collateralAsset, 1e18));
        console2.log("borrowAsset price: ", oracle2.getValueInEth(borrowAsset, 1e18));

        // PositionManager
        console2.log("positionManager proxy owner: ", positionManager.owner());
        console2.log("borrowAsset toggled: ", positionManager.isKnownAsset(borrowAsset));
        console2.log("collateralAsset toggled: ", positionManager.isKnownAsset(collateralAsset));

        /// Deposit/borrow/repay scenarios

        // Deposit liquidity
        /*IERC20(borrowAsset).approve(address(superPool), 1e17);
        superPool.deposit(1e17, 0xB290f2F3FAd4E540D0550985951Cdad2711ac34A);
        (address position, bool available) =
            portfolioLens.predictAddress(0xB290f2F3FAd4E540D0550985951Cdad2711ac34A, SALT);
        available;

        // Open new position, deposit, and borrow
        Action[] memory actions = new Action[](5);
        actions[0] = ActionUtils.newPosition(0xB290f2F3FAd4E540D0550985951Cdad2711ac34A, SALT);
        actions[1] = ActionUtils.deposit(address(collateralAsset), 2e17);
        actions[2] = ActionUtils.addToken(address(collateralAsset));
        actions[3] = ActionUtils.borrow(poolId, 1e16);
        actions[4] = ActionUtils.transfer(0xB290f2F3FAd4E540D0550985951Cdad2711ac34A, address(borrowAsset), 1e16);
        
        IERC20(collateralAsset).approve(address(positionManager), 2e17);
        positionManager.processBatch(position, actions);

        // Partially repay borrowed asset
        actions = new Action[](2);
        actions[0] = ActionUtils.deposit(address(borrowAsset), 1e10);
        actions[1] = ActionUtils.repay(poolId, 1e10);
        
        IERC20(borrowAsset).approve(address(positionManager), 1e10);
        positionManager.processBatch(position, actions);*/
    }
}
