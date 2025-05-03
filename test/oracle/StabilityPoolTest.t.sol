// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
 * @title StabilityPoolTest
 * @notice Production-ready tests for Stability Pool based positions
 */

import "../BaseTest.t.sol";
import "src/interfaces/IStabilityPool.sol";
import "src/interfaces/IOracle.sol";
import "src/tokens/StabilityPoolToken.sol";
import "src/oracle/FixedPriceOracle.sol";
import "forge-std/console2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Action, Operation} from "src/PositionManager.sol";
import {ActionUtils} from "test/utils/ActionUtils.sol";

// Interface for Position contract to access position data
interface IPosition {
    function getPositionAssets() external view returns (address[] memory);
    function getDebtPools() external view returns (uint256[] memory);
}

/**
 * @title StabilityPoolTest
 * @notice Simplified test for  Stability Pool collateral and borrowing
 */
contract StabilityPoolTest is BaseTest {
    using ActionUtils for Action;

    // Production contract addresses on Hyperliquid
    address constant STABILITY_POOL =
        0x576c9c501473e01aE23748de28415a74425eFD6b;
    address constant FEUSD = 0x02c6a2fA58cC01A18B8D9E00eA48d65E4dF26c70;

    address feUSDWhale = 0xabF0369530205aE56dD4C49629474C65d1168924;

    // Test amounts
    uint256 constant DEPOSIT_AMOUNT = 10e18; // 1 feUSD
    uint256 constant BORROW_AMOUNT = 5e18; // 0.5 asset1

    // Position salt
    bytes32 constant SALT = "_TEST";

    //  Stability Pool Token wrapper
    StabilityPoolToken stabilityPoolToken;

    // User's position
    address payable position;

    function setUp() public override {
        // Fork Hyperliquid
        vm.createSelectFork("https://rpc.hyperliquid.xyz/evm");

        // Base setup
        super.setUp();

        // Deploy our wrapper token
        stabilityPoolToken = new StabilityPoolToken(
            STABILITY_POOL,
            FEUSD,
            address(this)
        );

        // Give user some feUSD for testing
        deal(FEUSD, user, DEPOSIT_AMOUNT);

        // Setup protocol config
        setupProtocolConfig();
    }

    function setupProtocolConfig() internal {
        // Protocol owner setup
        vm.startPrank(protocolOwner);

        // Set asset values (simple fixed 1:1 with ETH for testing)
        protocol.riskEngine().setOracle(
            address(stabilityPoolToken),
            address(new FixedPriceOracle(1e18))
        );

        protocol.riskEngine().setOracle(
            address(asset1),
            address(new FixedPriceOracle(1e18))
        );

        // Set up allowable assets and operations
        protocol.positionManager().toggleKnownAsset(
            address(stabilityPoolToken)
        );
        protocol.positionManager().toggleKnownAsset(FEUSD);
        protocol.positionManager().toggleKnownSpender(STABILITY_POOL);

        // Allow stability pool functions
        protocol.positionManager().toggleKnownFunc(
            STABILITY_POOL,
            bytes4(keccak256("provideToSP(uint256,bool)"))
        );

        vm.stopPrank();

        // Pool owner setup
        vm.startPrank(poolOwner);

        // Set LTV for our stability pool token
        protocol.riskEngine().requestLtvUpdate(
            linearRatePool,
            address(stabilityPoolToken),
            0.8e18 // 80% LTV
        );

        protocol.riskEngine().acceptLtvUpdate(
            linearRatePool,
            address(stabilityPoolToken)
        );

        // Fund the pool
        asset1.mint(poolOwner, 100e18);
        asset1.approve(address(protocol.pool()), 100e18);
        protocol.pool().deposit(linearRatePool, 100e18, address(0));

        vm.stopPrank();
    }

    function testStabilityPoolToken() public {
        console2.log("===  STABILITY POOL TEST ===");

        // Create position with feUSD
        (address predictedPosition, ) = protocol.portfolioLens().predictAddress(
            user,
            SALT
        );
        position = payable(predictedPosition);

        vm.startPrank(user);

        // 1. Approve feUSD for transfer
        IERC20(FEUSD).approve(
            address(protocol.positionManager()),
            DEPOSIT_AMOUNT
        );

        // Prepare all actions in sequence
        Action[] memory actions = new Action[](5);

        // 2. Create new position and deposit feUSD
        actions[0] = ActionUtils.newPosition(user, SALT);
        actions[1] = ActionUtils.deposit(FEUSD, DEPOSIT_AMOUNT);

        // 3. Deposit into  Stability Pool
        actions[2] = Action({
            op: Operation.Exec,
            data: abi.encodePacked(
                STABILITY_POOL,
                uint256(0),
                abi.encodeWithSignature(
                    "provideToSP(uint256,bool)",
                    DEPOSIT_AMOUNT,
                    true
                )
            )
        });

        // 4. Add stability pool token as collateral
        actions[3] = ActionUtils.addToken(address(stabilityPoolToken));

        // 5. Borrow against position
        actions[4] = ActionUtils.borrow(linearRatePool, BORROW_AMOUNT);

        // Execute all operations atomically in a single transaction
        protocol.positionManager().processBatch(position, actions);

        // Final position health
        (uint256 totalAssetValue, uint256 totalDebtValue, ) = protocol
            .riskEngine()
            .getRiskData(position);
        uint256 ltv = (totalDebtValue * 1e18) / totalAssetValue / 1e14;
        uint256 healthFactor = protocol.riskModule().getPositionHealthFactor(
            position
        ) / 1e14;

        console2.log("\nFinal position:");
        console2.log(
            "   Asset value:",
            totalAssetValue / 1e18,
            "ETH ( deposit)"
        );
        console2.log("   Debt value:", totalDebtValue / 1e18, "ETH (borrowed)");
        console2.log("   LTV:", ltv / 100, "%");
        console2.log("   Health factor:", healthFactor / 100);

        vm.stopPrank();
    }
}
