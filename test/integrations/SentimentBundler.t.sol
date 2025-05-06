// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {Position} from "../../src/Position.sol";
import {PositionManager, Action, Operation} from "../../src/PositionManager.sol";
import {Pool} from "../../src/Pool.sol";
import {SentimentBundler} from "../../src/integrations/SentimentBundler.sol";
import {MockWETH} from "../mocks/MockWETH.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {console} from "forge-std/console.sol";

/// @title SentimentBundlerTest
/// @notice Tests for the SentimentBundler contract
contract SentimentBundlerTest is BaseTest {
    SentimentBundler public bundler;
    MockWETH public mockWeth;
    MockERC20 public borrowAsset;
    PositionManager public positionManager;
    Pool public pool;
    address public position;
    address public testUser = address(0x456);
    bytes32 public salt = bytes32(uint256(0x123));
    uint256 public constant ETH_AMOUNT = 1 ether;

    function setUp() public override {
        super.setUp();

        // Get the protocol contracts from BaseTest
        positionManager = protocol.positionManager();
        pool = protocol.pool();

        // Create mock assets
        mockWeth = new MockWETH();
        borrowAsset = new MockERC20("Borrow Asset", "BRWA", 18);

        // Set up the bundler
        bundler = new SentimentBundler(
            address(positionManager),
            address(mockWeth)
        );

        // Set up the user
        vm.deal(testUser, ETH_AMOUNT);
        borrowAsset.mint(testUser, 10 ether);

        // Configure the protocol
        vm.startPrank(protocolOwner);
        positionManager.toggleKnownAsset(address(mockWeth));
        positionManager.toggleKnownAsset(address(borrowAsset));
        vm.stopPrank();

        // Allow bundler to execute operations
        vm.startPrank(protocolOwner);
        positionManager.toggleKnownSpender(address(bundler));
        positionManager.toggleKnownFunc(
            address(mockWeth),
            MockWETH.deposit.selector
        );
        vm.stopPrank();
    }

    function testCreatePositionAndWrapETH() public {
        vm.startPrank(testUser);

        // Create action data for bundler multicall
        bytes[] memory callData = new bytes[](5);

        // Step 1: Create position with processBatch
        Action memory newPositionAction;
        (position, newPositionAction) = newPosition(testUser, salt);
        console.log("Position created at:", position);
        console.log("msg.sender for position creation:", msg.sender);

        Action[] memory createActions = new Action[](1);
        createActions[0] = newPositionAction;

        callData[0] = abi.encodeWithSelector(
            bundler.processBatch.selector,
            position,
            createActions
        );

        // Step 2: Wrap ETH in the bundler
        callData[1] = abi.encodeWithSelector(
            bundler.wrapNative.selector,
            ETH_AMOUNT
        );
        console.log("msg.sender for wrapNative:", msg.sender);

        // Step 3: Transfer WETH to position
        callData[2] = abi.encodeWithSelector(
            bundler.erc20Transfer.selector,
            address(mockWeth),
            position,
            ETH_AMOUNT
        );
        console.log("msg.sender for erc20Transfer:", msg.sender);

        // Step 4: Add WETH token to position's asset list
        Action memory addWethAction = addToken(address(mockWeth));
        Action[] memory wrapActions = new Action[](1);
        wrapActions[0] = addWethAction;

        callData[3] = abi.encodeWithSelector(
            bundler.processBatch.selector,
            position,
            wrapActions
        );
        console.log("msg.sender for addToken:", msg.sender);

        // Step 5: Check WETH balance in position
        callData[4] = abi.encodeWithSelector(
            bundler.erc20Transfer.selector,
            address(mockWeth),
            testUser,
            0 // Just to check balance, not actually transferring
        );

        // Send ETH with the call and execute multicall
        bundler.multicall{value: ETH_AMOUNT}(callData);
        console.log("Multicall executed with msg.sender:", msg.sender);

        vm.stopPrank();

        // Verify position has WETH
        assertEq(
            mockWeth.balanceOf(position),
            ETH_AMOUNT,
            "Position should have WETH balance"
        );
    }
}
