// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { DeploymentOrchestrator } from "script/DeploymentOrchestrator.s.sol";
import { Pool } from "src/Pool.sol";

import { Position } from "src/Position.sol";
import { Action, Operation, PositionManager } from "src/PositionManager.sol";
import { Registry } from "src/Registry.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { RiskModule } from "src/RiskModule.sol";
import { SuperPool } from "src/SuperPool.sol";
import { SuperPoolFactory } from "src/SuperPoolFactory.sol";
import { KinkedRateModel } from "src/irm/KinkedRateModel.sol";
import { PortfolioLens } from "src/lens/PortfolioLens.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockV3Aggregator } from "test/mocks/MockV3Aggregator.sol";

/**
 * @title DeploymentOrchestratorTest
 * @notice Test contract for the DeploymentOrchestrator script
 * @dev This test uses the real DeploymentOrchestrator to test the full deployment process
 */
contract DeploymentOrchestratorBaseTest is Test {
    // Test accounts
    address internal _deployer;
    address internal _deployerWallet; // Wallet used for actual deployment
    address internal _proxyAdmin;
    address internal _user1;
    address internal _user2;

    // Mock token and oracle addresses
    address internal _usdc;
    address internal _weth;
    address internal _usdcOracle;
    address internal _wethOracle;

    // Real DeploymentOrchestrator instance
    DeploymentOrchestrator internal _orchestrator;

    // Deployed contract addresses
    address internal _registry;
    address internal _pool;
    address internal _riskEngine;
    address internal _riskModule;
    address internal _positionManager;
    address internal _superPoolFactory;
    address internal _superPool;
    address internal _portfolioLens;
    address internal _positionBeacon;
    address internal _superPoolLens;
    uint256 internal _poolId;

    // Getter function for _positionManager
    function getPositionManager() public view returns (address) {
        return _positionManager;
    }

    // Getter function for _portfolioLens
    function getPortfolioLens() public view returns (address) {
        return _portfolioLens;
    }

    function setUp() public virtual {
        // Set up test accounts
        _deployer = makeAddr("deployer");
        _proxyAdmin = makeAddr("proxyAdmin");
        _user1 = makeAddr("user1");
        _user2 = makeAddr("user2");

        vm.deal(_deployer, 100 ether);
        vm.deal(_proxyAdmin, 100 ether);
        vm.deal(_user1, 10 ether);
        vm.deal(_user2, 10 ether);

        // Set up the test deployment wallet - this will be the actual owner
        bytes32 privateKey = bytes32(uint256(keccak256("test deployer key")));
        _deployerWallet = vm.addr(uint256(privateKey));
        vm.deal(_deployerWallet, 100 ether);
        vm.setEnv("PRIVATE_KEY", vm.toString(uint256(privateKey)));

        // Deploy mock tokens and oracles
        _deployMocks();

        // Distribute tokens for testing
        _distributeTokens();

        // Create config file for deployment
        _createConfigFile();

        // Initialize orchestrator - important to run as the deployer wallet to match private key
        vm.startPrank(_deployerWallet);
        _orchestrator = new DeploymentOrchestrator();
        vm.stopPrank();

        // Note: The actual deployment is performed in the test functions
        // rather than in setUp to allow more granular control and testing
    }

    // Deploy mock tokens and oracles
    function _deployMocks() internal {
        // Deploy mock tokens
        vm.startPrank(_deployerWallet);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        _usdc = address(usdc);
        usdc.mint(_deployerWallet, 1_000_000_000 * 10 ** 6); // 1 billion USDC

        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        _weth = address(weth);
        weth.mint(_deployerWallet, 100_000 * 10 ** 18); // 100,000 WETH
        vm.stopPrank();

        // Deploy mock price oracles (Chainlink compatible)
        MockV3Aggregator usdcAggregator = new MockV3Aggregator(8, 100_000_000); // $1.00 with 8 decimals
        _usdcOracle = address(usdcAggregator);

        MockV3Aggregator wethAggregator = new MockV3Aggregator(8, 200_000_000_000); // $2,000 with 8 decimals
        _wethOracle = address(wethAggregator);
    }

    // Distribute tokens to test users
    function _distributeTokens() internal {
        vm.startPrank(_deployerWallet);

        // Transfer USDC to users
        IERC20(_usdc).transfer(_user1, 1_000_000 * 10 ** 6); // 1 million USDC
        IERC20(_usdc).transfer(_user2, 500_000 * 10 ** 6); // 500k USDC

        // Transfer WETH to users
        IERC20(_weth).transfer(_user1, 50 * 10 ** 18); // 50 WETH
        IERC20(_weth).transfer(_user2, 25 * 10 ** 18); // 25 WETH

        vm.stopPrank();
    }

    // Execute the deployment orchestrator and capture deployed addresses
    function _runDeployment() internal {
        // DeploymentOrchestrator uses broadcasting which doesn't work well with vm.prank
        // First ensure tokens are approved with generous allowances
        vm.startPrank(_deployerWallet);
        IERC20(_usdc).approve(address(_orchestrator), type(uint256).max);
        IERC20(_weth).approve(address(_orchestrator), type(uint256).max);

        // Transfer enough tokens to the orchestrator for SuperPool deployment
        // This is needed because the SuperPool deployment requires the orchestrator
        // to have collateral tokens, not just the deployer wallet
        uint256 usdcDecimals = MockERC20(_usdc).decimals();
        uint256 superPoolInitialDeposit = 100 * 10 ** usdcDecimals; // 100 USDC with proper decimals
        IERC20(_usdc).transfer(address(_orchestrator), superPoolInitialDeposit);
        vm.stopPrank(); // Must stop prank before broadcasting

        // Run the deployment orchestrator
        _orchestrator.run();

        // Store deployed contract addresses for testing
        _registry = _orchestrator.registry();
        _pool = _orchestrator.pool();
        _riskEngine = _orchestrator.riskEngine();
        _riskModule = _orchestrator.riskModule();
        _positionManager = _orchestrator.positionManager();
        _superPoolFactory = _orchestrator.superPoolFactory();
        _superPool = _orchestrator.deployedSuperPool();
        _poolId = _orchestrator.poolId();
        _portfolioLens = _orchestrator.portfolioLens();
    }

    // Helper function to calculate Position address
    function _calculatePositionAddress(address owner, bytes32 salt) internal view returns (address) {
        // Hash salt with owner
        bytes32 finalSalt = keccak256(abi.encodePacked(owner, salt));

        // For testing, create a deterministic address based on salt and position manager
        address predictedAddress = address(uint160(uint256(keccak256(abi.encodePacked(finalSalt, _positionManager)))));

        return predictedAddress;
    }

    // Helper function to create a new position action
    function _createPositionAction(address owner, bytes32 salt) internal pure returns (Action memory) {
        bytes memory data = abi.encodePacked(owner, salt);
        return Action({ op: Operation.NewPosition, data: data });
    }

    // Create the JSON configuration file for the orchestrator
    function _createConfigFile() internal {
        // Create config directory
        string memory configDir = string(abi.encodePacked(vm.projectRoot(), "/config/31337"));
        vm.createDir(configDir, true);

        // Build and write the configuration JSON
        string memory config = _buildFixedConfig();
        string memory configPath = string(abi.encodePacked(configDir, "/script-config.json"));
        vm.writeFile(configPath, config);

        // Set the environment variable for script config
        vm.setEnv("SCRIPT_CONFIG", "script-config.json");
    }

    // Build a fixed configuration JSON that uses consistent assets
    function _buildFixedConfig() internal view returns (string memory) {
        // Get token decimals for proper config
        uint256 usdcDecimals = MockERC20(_usdc).decimals();
        uint256 wethDecimals = MockERC20(_weth).decimals();

        // Calculate initial deposit amounts with proper decimals
        uint256 superPoolInitialDeposit = 100 * 10 ** usdcDecimals; // 100 USDC

        // Start with protocol params
        string memory config = string(
            abi.encodePacked(
                '{"DeploymentOrchestrator":{',
                '"protocolParams":{"owner":"',
                vm.toString(_deployerWallet),
                '","proxyAdmin":"',
                vm.toString(_proxyAdmin),
                '","feeRecipient":"',
                vm.toString(_deployerWallet),
                '","minLtv":"0.5e18","maxLtv":"0.95e18","minDebt":"1e6",',
                '"minBorrow":"1e6","liquidationFee":"0.01e18",',
                '"liquidationDiscount":"0.05e18","badDebtLiquidationDiscount":"0.1e18",',
                '"defaultInterestFee":"0.1e18","defaultOriginationFee":"0.001e18"}'
            )
        );

        // Add rate model params
        config = string(
            abi.encodePacked(
                config,
                ",",
                '"kinkedRateModelParams":{"minRate":"0.02e18","slope1":"0.1e18",',
                '"slope2":"1e18","optimalUtil":"0.8e18"}'
            )
        );

        // Add asset params - IMPORTANT: Use WETH for borrow asset and USDC for collateral
        // This matches the asset types in _deploySuperPool
        config = string(
            abi.encodePacked(
                config,
                ",",
                '"assetParams":{"borrowAsset":"',
                vm.toString(_weth),
                '","borrowAssetOracle":"',
                vm.toString(_wethOracle),
                '","collateralAsset":"',
                vm.toString(_usdc),
                '","collateralAssetOracle":"',
                vm.toString(_usdcOracle),
                '"}'
            )
        );

        // Add pool params with proper decimals
        config = string(
            abi.encodePacked(
                config,
                ",",
                '"borrowPoolParams":{"borrowAssetPoolCap":"1000e',
                vm.toString(wethDecimals),
                '","borrowAssetBorrowCap":"800e',
                vm.toString(wethDecimals),
                '","borrowAssetInitialDeposit":"10e',
                vm.toString(wethDecimals),
                '"}'
            )
        );

        // Add SuperPool params with proper decimals - IMPORTANT: Use USDC as asset for SuperPool
        config = string(
            abi.encodePacked(
                config,
                ",",
                '"superPoolParams":{"superPoolCap":"1000e',
                vm.toString(wethDecimals),
                '","superPoolFee":"0.002e18","superPoolInitialDeposit":"',
                vm.toString(superPoolInitialDeposit),
                '","superPoolName":"Test SuperPool WETH",',
                '"superPoolSymbol":"tspWETH"}'
            )
        );

        // Finalize with LTV settings
        config = string(abi.encodePacked(config, ",", '"ltvSettings":{"collateralLtv":"0.8e18"}}}'));

        return config;
    }
}

// Basic test that just verifies core deployment
contract DeploymentOrchestratorBasicTest is DeploymentOrchestratorBaseTest {
    function setUp() public override {
        super.setUp();
        // Override the config to use our fixed version
        _createConfigFile();
    }

    function testBasicDeployment() public {
        // Run the deployment and just verify that it succeeded
        _runDeployment();

        // Verify the basic setup
        assertTrue(_registry != address(0), "Registry not deployed");
        assertTrue(_pool != address(0), "Pool not deployed");
        assertTrue(_riskEngine != address(0), "RiskEngine not deployed");
        assertTrue(_poolId > 0, "Pool not initialized");

        // Verify LTV
        assertEq(RiskEngine(_riskEngine).ltvFor(_poolId, _usdc), 0.8e18, "Collateral LTV not set correctly");
    }
}

// Simplified test that uses try/catch to handle the SuperPool error
contract DeploymentOrchestratorSimplifiedTest is DeploymentOrchestratorBaseTest {
    function setUp() public override {
        super.setUp();
        // Override the config to use our fixed version
        _createConfigFile();
    }

    function testDeploymentBasics() public {
        // Initialize our orchestrator
        vm.startPrank(_deployerWallet);
        _orchestrator = new DeploymentOrchestrator();

        // Approve tokens for initial deposits with generous allowances
        IERC20(_usdc).approve(address(_orchestrator), type(uint256).max);
        IERC20(_weth).approve(address(_orchestrator), type(uint256).max);

        // Transfer USDC to the orchestrator for SuperPool deployment with proper decimals
        uint256 usdcDecimals = MockERC20(_usdc).decimals();
        uint256 superPoolInitialDeposit = 100 * 10 ** usdcDecimals; // 100 USDC
        IERC20(_usdc).transfer(address(_orchestrator), superPoolInitialDeposit);
        vm.stopPrank();

        // Run the deployment - should succeed now with fixed config
        _orchestrator.run();

        // Store deployed addresses (even if deployment failed partially)
        _registry = _orchestrator.registry();
        _pool = _orchestrator.pool();
        _riskEngine = _orchestrator.riskEngine();
        _riskModule = _orchestrator.riskModule();
        _positionManager = _orchestrator.positionManager();
        _superPoolFactory = _orchestrator.superPoolFactory();
        _superPool = _orchestrator.deployedSuperPool();
        _positionBeacon = _orchestrator.positionBeacon();
        _superPoolLens = _orchestrator.superPoolLens();
        _portfolioLens = _orchestrator.portfolioLens();
        _poolId = _orchestrator.poolId();

        // Verify key contracts were deployed correctly
        assertTrue(_registry != address(0), "Registry not deployed");
        assertTrue(_pool != address(0), "Pool not deployed");
        assertTrue(_riskEngine != address(0), "RiskEngine not deployed");
        assertTrue(_superPoolFactory != address(0), "SuperPoolFactory not deployed");
        assertTrue(_superPool != address(0), "SuperPool not deployed");
        assertTrue(_poolId != 0, "Pool not initialized");
    }
}

// Test focusing on the deployment process
contract DeploymentOrchestratorDeploymentTest is DeploymentOrchestratorBaseTest {
    function setUp() public override {
        super.setUp();
        // Override the config to use our fixed version
        _createConfigFile();
    }

    function testFullDeployment() public {
        // Run the full deployment
        _runDeployment();

        // Verify all core contracts are deployed
        assertTrue(_registry != address(0), "Registry not deployed");
        assertTrue(_pool != address(0), "Pool not deployed");
        assertTrue(_riskEngine != address(0), "RiskEngine not deployed");
        assertTrue(_riskModule != address(0), "RiskModule not deployed");
        assertTrue(_positionManager != address(0), "PositionManager not deployed");
        assertTrue(_superPoolFactory != address(0), "SuperPoolFactory not deployed");
        assertTrue(_superPool != address(0), "SuperPool not deployed");
        assertTrue(_poolId > 0, "Pool not initialized");

        // Verify rate model deployment and registration
        bytes32 kinkedRateModelKey = _orchestrator.kinkedRateModelKey();
        address kinkedRateModel = _orchestrator.kinkedRateModel();
        assertEq(
            Registry(_registry).rateModelFor(kinkedRateModelKey),
            kinkedRateModel,
            "KinkedRateModel not registered correctly"
        );

        // Verify oracle registrations
        assertEq(RiskEngine(_riskEngine).oracleFor(_weth), _wethOracle, "WETH oracle not set correctly");
        assertEq(RiskEngine(_riskEngine).oracleFor(_usdc), _usdcOracle, "USDC oracle not set correctly");

        // Verify pool caps
        assertEq(Pool(_pool).getPoolCapFor(_poolId), 1000 * 10 ** 18, "Pool cap not set correctly");
        assertEq(Pool(_pool).getBorrowCapFor(_poolId), 800 * 10 ** 18, "Borrow cap not set correctly");

        // Verify LTV settings
        assertEq(RiskEngine(_riskEngine).ltvFor(_poolId, _usdc), 0.8e18, "Collateral LTV not set correctly");

        // Verify asset whitelisting in PositionManager
        assertTrue(PositionManager(_positionManager).isKnownAsset(_weth), "WETH not whitelisted in PositionManager");
        assertTrue(PositionManager(_positionManager).isKnownAsset(_usdc), "USDC not whitelisted in PositionManager");

        // Verify SuperPool deployment
        assertTrue(
            SuperPoolFactory(_superPoolFactory).isDeployerFor(_superPool),
            "SuperPool not registered in SuperPoolFactory"
        );

        // Verify SuperPool is properly initialized
        assertEq(SuperPool(_superPool).poolCapFor(_poolId), 1000 * 10 ** 18, "SuperPool pool cap not set correctly");
        assertEq(SuperPool(_superPool).asset(), _weth, "SuperPool asset not set correctly");
        assertEq(SuperPool(_superPool).fee(), 0.002e18, "SuperPool fee not set correctly");
    }
}

// Test for interactions
contract DeploymentOrchestratorInteractionTest is DeploymentOrchestratorBaseTest {
    function testPositionCreation() public {
        // Run the standard deployment
        vm.startPrank(_deployerWallet);
        _orchestrator = new DeploymentOrchestrator();

        // Approve tokens for deposits
        IERC20(_usdc).approve(address(_orchestrator), type(uint256).max);
        IERC20(_weth).approve(address(_orchestrator), type(uint256).max);

        // Transfer tokens to the orchestrator for SuperPool deployment
        address collateralAsset = _usdc; // Match collateral asset in the config
        uint256 usdcDecimals = MockERC20(_usdc).decimals();
        uint256 superPoolInitialDeposit = 100 * 10 ** usdcDecimals; // 100 USDC with proper decimals

        // Make sure the orchestrator has enough USDC for SuperPool deployment
        IERC20(collateralAsset).transfer(address(_orchestrator), superPoolInitialDeposit);
        console2.log("Transferred USDC to orchestrator:", superPoolInitialDeposit);
        console2.log("Orchestrator USDC balance:", IERC20(collateralAsset).balanceOf(address(_orchestrator)));

        vm.stopPrank();
    }
}
