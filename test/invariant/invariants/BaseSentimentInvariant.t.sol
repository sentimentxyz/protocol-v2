// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { Deploy } from "script/Deploy.s.sol";
import { Pool } from "src/Pool.sol";
import { Position } from "src/Position.sol";
import { PositionManager } from "src/PositionManager.sol";

import { Action, Operation, PositionManager } from "src/PositionManager.sol";
import { Registry } from "src/Registry.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { RiskModule } from "src/RiskModule.sol";

import { SuperPool } from "src/SuperPool.sol";

import { SuperPoolFactory } from "src/SuperPoolFactory.sol";
import { FixedRateModel } from "src/irm/FixedRateModel.sol";
import { LinearRateModel } from "src/irm/LinearRateModel.sol";

import { PortfolioLens } from "src/lens/PortfolioLens.sol";
import { SuperPoolLens } from "src/lens/SuperPoolLens.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockPool } from "test/mocks/MockPool.sol";
import { MockPositionManager } from "test/mocks/MockPositionManager.sol";
import { MockRiskModule } from "test/mocks/MockRiskModule.sol";
import { MockSuperPool } from "test/mocks/MockSuperPool.sol";
import { MockSuperPoolFactory } from "test/mocks/MockSuperPoolFactory.sol";
import { OracleMock } from "test/mocks/OracleMock.sol";

import { FuzzBase } from "@fuzzlib/FuzzBase.sol";

// forgefmt: disable-start
/**************************************************************************************************************/
/*** BaseSentimentInvariant contains the setup for the Sentiment Protocol.                                  ***/
/*** It configures 5 base pools with mixed rate strategies                                                  ***/
/*** It also configures 2 SuperPools with mixed base pools                                                  ***/
/**************************************************************************************************************/
// forgefmt: disable-end

abstract contract BaseSentimentInvariant is Test, FuzzBase {
    struct DeployParams {
        address owner;
        address proxyAdmin;
        address feeRecipient;
        uint256 minLtv;
        uint256 maxLtv;
        uint256 minDebt;
        uint256 minBorrow;
        uint256 liquidationFee;
        uint256 liquidationDiscount;
        uint256 badDebtLiquidationDiscount;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            BASE INVARIANT VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    // keccak(SENTIMENT_POSITION_MANAGER_KEY)
    bytes32 constant SENTIMENT_POSITION_MANAGER_KEY =
        0xd4927490fbcbcafca716cca8e8c8b7d19cda785679d224b14f15ce2a9a93e148;
    // keccak(SENTIMENT_POOL_KEY)
    bytes32 constant SENTIMENT_POOL_KEY = 0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728;
    // keccak(SENTIMENT_RISK_ENGINE_KEY)
    bytes32 constant SENTIMENT_RISK_ENGINE_KEY =
        0x5b6696788621a5d6b5e3b02a69896b9dd824ebf1631584f038a393c29b6d7555;
    // keccak(SENIMENT_POSITION_BEACON_KEY)
    bytes32 constant SENTIMENT_POSITION_BEACON_KEY =
        0x6e7384c78b0e09fb848f35d00a7b14fc1ad10ae9b10117368146c0e09b6f2fa2;
    // keccak(SENTIMENT_RISK_MODULE_KEY)
    bytes32 constant SENTIMENT_RISK_MODULE_KEY =
        0x881469d14b8443f6c918bdd0a641e9d7cae2592dc28a4f922a2c4d7ca3d19c77;

    bytes32 FIXED_RATE_MODEL_KEY = 0xeba2c14de8b8ca05a15d7673453a0a3b315f122f56770b8bb643dc4bfbcf326b;
    bytes32 LINEAR_RATE_MODEL_KEY = 0x7922391f605f567c8e61c33be42b581e2f71019b5dce3c47110ad332b7dbd68c;
    bytes32 FIXED_RATE_MODEL2_KEY = 0x65347a20305cbd3ca20cb81ec8a2261639f4e635b4b5f3039a9aa5e7e03f41a7;
    bytes32 LINEAR_RATE_MODEL2_KEY = 0xd61dc960093d99acc135f998430c41a550d91de727e66a94fd8e7a8a24d99ecf;

    address user0 = vm.addr(uint256(keccak256("User0")));
    address user1 = vm.addr(uint256(keccak256("User1")));
    address user2 = vm.addr(uint256(keccak256("User2")));
    address user3 = vm.addr(uint256(keccak256("User3")));
    address user4 = vm.addr(uint256(keccak256("User4")));
    address user5 = vm.addr(uint256(keccak256("User5")));
    address[] users = [user0, user1, user2, user3, user4, user5];

    uint256[] poolIds = new uint256[](4);
    address[] tokens = new address[](2);

    address lender = vm.addr(uint256(keccak256("lender")));
    address poolOwner = vm.addr(uint256(keccak256("poolOwner")));
    address proxyAdmin = vm.addr(uint256(keccak256("proxyAdmin")));
    address protocolOwner = vm.addr(uint256(keccak256("protocolOwner")));
    address feeReceiver = vm.addr(uint256(keccak256("feeReceiver")));

    uint256 fixedRatePool;
    uint256 linearRatePool;
    uint256 fixedRatePool2;
    uint256 linearRatePool2;
    uint256 alternateAssetPool;

    /*//////////////////////////////////////////////////////////////////////////
                                   TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    // registry
    Registry registry;
    // superpool factory
    MockSuperPoolFactory superPoolFactory;
    // position manager
    address positionManagerImpl;
    MockPositionManager positionManager;
    // risk
    RiskEngine riskEngine;
    MockRiskModule riskModule;
    // pool
    address poolImpl;
    MockPool pool;
    // super pools
    MockSuperPool superPool1;
    MockSuperPool superPool2;

    // position
    address positionBeacon;
    // lens
    SuperPoolLens superPoolLens;
    PortfolioLens portfolioLens;

    OracleMock assetOracle;

    MockERC20 asset1;
    MockERC20 asset2;

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setup() internal virtual {
        DeployParams memory params = DeployParams({
            owner: protocolOwner,
            proxyAdmin: proxyAdmin,
            feeRecipient: address(this),
            minLtv: 2e17,
            maxLtv: 8e17,
            minDebt: 0,
            minBorrow: 0,
            liquidationFee: 0,
            liquidationDiscount: 200_000_000_000_000_000,
            badDebtLiquidationDiscount: 1e16
        });

        asset1 = new MockERC20("Asset1", "ASSET1", 18);
        tokens[0] = address(asset1);
        asset2 = new MockERC20("Asset2", "ASSET2", 18);
        tokens[1] = address(asset2);

        assetOracle = new OracleMock(tokens, 10e18, 1e18);

        _run(params);

        address fixedRateModel = address(new FixedRateModel(1e18));
        address linearRateModel = address(new LinearRateModel(1e18, 2e18));
        address fixedRateModel2 = address(new FixedRateModel(2e18));
        address linearRateModel2 = address(new LinearRateModel(2e18, 3e18));

        vm.prank(protocolOwner);
        Registry(registry).setAddress(FIXED_RATE_MODEL_KEY, fixedRateModel);
        vm.prank(protocolOwner);
        Registry(registry).setAddress(LINEAR_RATE_MODEL_KEY, linearRateModel);
        vm.prank(protocolOwner);
        Registry(registry).setAddress(FIXED_RATE_MODEL2_KEY, fixedRateModel2);
        vm.prank(protocolOwner);
        Registry(registry).setAddress(LINEAR_RATE_MODEL2_KEY, linearRateModel2);

        vm.prank(poolOwner);
        fixedRatePool =
            pool.initializePool(poolOwner, address(asset1), type(uint128).max, FIXED_RATE_MODEL_KEY);
        poolIds[0] = fixedRatePool;
        vm.prank(poolOwner);
        linearRatePool =
            pool.initializePool(poolOwner, address(asset1), type(uint128).max, LINEAR_RATE_MODEL_KEY);
        poolIds[1] = linearRatePool;
        vm.prank(poolOwner);
        fixedRatePool2 =
            pool.initializePool(poolOwner, address(asset1), type(uint128).max, FIXED_RATE_MODEL2_KEY);
        poolIds[2] = fixedRatePool2;
        vm.prank(poolOwner);
        linearRatePool2 =
            pool.initializePool(poolOwner, address(asset1), type(uint128).max, LINEAR_RATE_MODEL2_KEY);
        poolIds[3] = linearRatePool2;

        vm.prank(poolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.75e18);
        vm.prank(poolOwner);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset1));
        vm.prank(poolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset2), 0.75e18);
        vm.prank(poolOwner);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset2));

        vm.prank(poolOwner);
        riskEngine.requestLtvUpdate(linearRatePool2, address(asset1), 0.75e18);
        vm.prank(poolOwner);
        riskEngine.acceptLtvUpdate(linearRatePool2, address(asset1));
        vm.prank(poolOwner);
        riskEngine.requestLtvUpdate(linearRatePool2, address(asset2), 0.75e18);
        vm.prank(poolOwner);
        riskEngine.acceptLtvUpdate(linearRatePool2, address(asset2));

        vm.prank(poolOwner);
        riskEngine.requestLtvUpdate(fixedRatePool, address(asset1), 0.75e18);
        vm.prank(poolOwner);
        riskEngine.acceptLtvUpdate(fixedRatePool, address(asset1));
        vm.prank(poolOwner);
        riskEngine.requestLtvUpdate(fixedRatePool, address(asset2), 0.75e18);
        vm.prank(poolOwner);
        riskEngine.acceptLtvUpdate(fixedRatePool, address(asset2));

        vm.prank(poolOwner);
        riskEngine.requestLtvUpdate(fixedRatePool2, address(asset1), 0.75e18);
        vm.prank(poolOwner);
        riskEngine.acceptLtvUpdate(fixedRatePool2, address(asset1));
        vm.prank(poolOwner);
        riskEngine.requestLtvUpdate(fixedRatePool2, address(asset2), 0.75e18);
        vm.prank(poolOwner);
        riskEngine.acceptLtvUpdate(fixedRatePool2, address(asset2));

        superPool1 = MockSuperPool(
            superPoolFactory.deploySuperPool(
                poolOwner, address(asset1), feeReceiver, 0.01 ether, 1_000_000 ether, "test", "test"
            )
        );

        superPool2 = MockSuperPool(
            superPoolFactory.deploySuperPool(
                poolOwner, address(asset1), feeReceiver, 0.01 ether, 1_000_000 ether, "test", "test"
            )
        );

        vm.prank(poolOwner);
        superPool1.addPool(linearRatePool, 50_000 ether);
        vm.prank(poolOwner);
        superPool1.addPool(fixedRatePool2, 50_000 ether);

        vm.prank(poolOwner);
        superPool2.addPool(linearRatePool2, 75_000 ether);
        vm.prank(poolOwner);
        superPool2.addPool(fixedRatePool, 25_000 ether);

        asset1.mint(user0, 10_000e18);
        asset2.mint(user0, 10e18);
        asset1.mint(user1, 10_000e18);
        asset2.mint(user1, 10e18);
        asset1.mint(user2, 10_000e18);
        asset2.mint(user2, 10e18);
        asset1.mint(user3, 10_000e18);
        asset2.mint(user3, 10e18);
        asset1.mint(user4, 10_000e18);
        asset2.mint(user4, 10e18);
        asset1.mint(user5, 10_000e18);
        asset2.mint(user5, 10e18);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function randomAddress(uint256 seed) internal view returns (address) {
        return users[bound(seed, 0, users.length - 1)];
    }

    function randomPoolId(uint256 seed) internal view returns (uint256) {
        return poolIds[bound(seed, 0, poolIds.length - 1)];
    }

    function randomToken(uint256 seed) internal view returns (address) {
        return tokens[bound(seed, 0, tokens.length - 1)];
    }

    function assertApproxGeAbs(uint a, uint b, uint maxDelta) internal {
        if (!(a >= b)) {
            uint dt = b - a;
            if (dt > maxDelta) {
                emit log                ("Error: a >=~ b not satisfied [uint]");
                emit log_named_uint     ("   Value a", a);
                emit log_named_uint     ("   Value b", b);
                emit log_named_uint     (" Max Delta", maxDelta);
                emit log_named_uint     ("     Delta", dt);
                fail();
            }
        }
    }

    function assertApproxLeAbs(uint a, uint b, uint maxDelta, string memory reason) internal {
        if (!(a <= b)) {
            uint dt = a - b;
            if (dt > maxDelta) {
                emit log                ("Error: a <=~ b not satisfied [uint]");
                emit log_named_uint     ("   Value a", a);
                emit log_named_uint     ("   Value b", b);
                emit log_named_uint     (" Max Delta", maxDelta);
                emit log_named_uint     ("     Delta", dt);
                fl.t(false, reason);
            }
        } else {
            fl.t(true, "a == b");
        }
    }

    function _run(DeployParams memory _params) internal {
        // registry
        registry = new Registry();
        // risk
        riskEngine = new RiskEngine(address(registry), _params.minLtv, _params.maxLtv);
        riskEngine.transferOwnership(_params.owner);
        riskModule = new MockRiskModule(address(registry), _params.liquidationDiscount, _params.badDebtLiquidationDiscount);

        vm.prank(protocolOwner);
        riskEngine.setOracle(address(asset1), address(assetOracle));
        vm.prank(protocolOwner);
        riskEngine.setOracle(address(asset2), address(assetOracle));
        // pool
        poolImpl = address(new MockPool());
        bytes memory poolInitData =
            abi.encodeWithSelector(
                Pool.initialize.selector, 
                _params.owner, 
                address(registry), 
                _params.feeRecipient,
                _params.minBorrow,
                _params.minDebt
            );
        pool = MockPool(address(new TransparentUpgradeableProxy(poolImpl, _params.proxyAdmin, poolInitData)));
        // super pool factory
        superPoolFactory = new MockSuperPoolFactory(address(pool));
        // position manager
        positionManagerImpl = address(new MockPositionManager());
        bytes memory posmgrInitData = abi.encodeWithSelector(
            PositionManager.initialize.selector, _params.owner, address(registry), _params.liquidationFee
        );
        positionManager = MockPositionManager(
            address(new TransparentUpgradeableProxy(positionManagerImpl, _params.proxyAdmin, posmgrInitData))
        );
        // position
        address positionImpl = address(new Position(address(pool), address(positionManager)));
        positionBeacon = address(new UpgradeableBeacon(positionImpl));
        // lens
        superPoolLens = new SuperPoolLens(address(pool), address(riskEngine));
        portfolioLens = new PortfolioLens(address(pool), address(riskEngine), address(positionManager));
        // register modules
        registry.setAddress(SENTIMENT_POSITION_MANAGER_KEY, address(positionManager));
        registry.setAddress(SENTIMENT_POOL_KEY, address(pool));
        registry.setAddress(SENTIMENT_RISK_ENGINE_KEY, address(riskEngine));
        registry.setAddress(SENTIMENT_POSITION_BEACON_KEY, address(positionBeacon));
        registry.setAddress(SENTIMENT_RISK_MODULE_KEY, address(riskModule));
        registry.transferOwnership(_params.owner);
        // update module addresses
        pool.updateFromRegistry();
        positionManager.updateFromRegistry();
        riskEngine.updateFromRegistry();
        riskModule.updateFromRegistry();

        vm.prank(positionManager.owner());
        positionManager.toggleKnownAddress(address(asset1));
        vm.prank(positionManager.owner());
        positionManager.toggleKnownAddress(address(asset2));
    }
}
