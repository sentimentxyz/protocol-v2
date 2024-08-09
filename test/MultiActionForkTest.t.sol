// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./mocks/MockERC20.sol";
import "./utils/ActionUtils.sol";
import "forge-std/Test.sol";
import "src/Pool.sol";
import "src/PositionManager.sol";
import "src/SuperPool.sol";
import "src/lens/PortfolioLens.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

interface IWETH9 {
    function deposit() external payable;

    function withdraw(uint256 _amount) external;

    function approve(address spender, uint256 amount) external returns (bool);
}

contract MultiActionForkTest is Test {
    using Math for uint256;

    address USER;
    bytes32 constant SALT = bytes32(uint256(0x123456));
    uint256 constant SP_DEPOSIT_AMT = 1e18;
    uint256 constant BP_BORROW_AMT = 1e15;

    Pool constant POOL = Pool(0x2F6720f5D1377AF8EDC8A66f3BA3D14C7941e6A8);
    IWETH9 constant WETH = IWETH9(0x980B62Da83eFf3D4576C647993b0c1D7faf17c73);
    SuperPool constant seWETH = SuperPool(0x800B1240F6C2fe5C8E0B97A48f2E81Acd0B36f33);
    PositionManager constant POS_MGR = PositionManager(0x2e9f6E5A33bC9163d11a5a9DB3ba5427761F03bC);
    PortfolioLens constant PORTFOLIO_LENS = PortfolioLens(0x052332eec108E9b3b18026D6B7B5A54507B208e5);

    uint256 constant WETH_POOL =
        43_880_796_985_635_196_139_849_623_724_192_798_402_149_558_214_364_489_328_040_456_202_003_758_251_862;

    function setUp() public {
        USER = makeAddr("user");
    }

    function testSuperPoolDeposit() public returns (uint256 shares) {
        vm.deal(USER, SP_DEPOSIT_AMT);

        vm.startPrank(USER);
        WETH.deposit{ value: SP_DEPOSIT_AMT }();
        WETH.approve(address(seWETH), SP_DEPOSIT_AMT);
        shares = seWETH.deposit(SP_DEPOSIT_AMT, USER);
        vm.stopPrank();
    }

    function testCreatePosition() public returns (address position) {
        (position,) = PORTFOLIO_LENS.predictAddress(USER, SALT);
        console2.log("Position: ", position);

        Action memory action = ActionUtils.newPosition(USER, SALT);
        vm.prank(USER);
        POS_MGR.process(position, action);
    }

    function testDeposit() public returns (address) {
        uint256 shares = testSuperPoolDeposit();
        address position = testCreatePosition();

        Action[] memory actions = new Action[](2);
        actions[0] = ActionUtils.deposit(address(seWETH), shares);
        actions[1] = ActionUtils.addToken(address(seWETH));

        vm.startPrank(USER);
        seWETH.approve(address(POS_MGR), shares);
        POS_MGR.processBatch(position, actions);
        vm.stopPrank();

        return position;
    }

    function testBorrowAndWithdraw() public {
        address position = testDeposit();

        Action[] memory actions = new Action[](2);
        actions[0] = ActionUtils.borrow(WETH_POOL, BP_BORROW_AMT);
        actions[1] = ActionUtils.transfer(USER, address(WETH), type(uint256).max);

        vm.prank(USER);
        POS_MGR.processBatch(position, actions);
    }

    function testBorrowAndExec() public {
        address position = testDeposit();

        (,,,,,, uint256 originationFee,,,,) = POOL.poolDataFor(WETH_POOL);
        console2.log("originationFee: ", originationFee);
        uint256 fee = BP_BORROW_AMT.mulDiv(originationFee, 1e18);
        uint256 borrowAmtNetFees = BP_BORROW_AMT - fee;
        console2.log("borrowAmtNetFees: ", borrowAmtNetFees);

        bytes memory data = abi.encodeWithSelector(SuperPool.deposit.selector, borrowAmtNetFees, position);

        Action[] memory actions = new Action[](3);
        actions[0] = ActionUtils.borrow(WETH_POOL, BP_BORROW_AMT);
        actions[1] = ActionUtils.approve(address(seWETH), address(WETH), borrowAmtNetFees);
        actions[2] = ActionUtils.exec(address(seWETH), 0, data);

        vm.prank(USER);
        POS_MGR.processBatch(position, actions);
    }

    function testMultiAction() public {
        vm.deal(USER, SP_DEPOSIT_AMT);

        vm.startPrank(USER);
        WETH.deposit{ value: SP_DEPOSIT_AMT }();
        WETH.approve(address(seWETH), SP_DEPOSIT_AMT);
        uint256 shares = seWETH.deposit(SP_DEPOSIT_AMT, USER);
        vm.stopPrank();

        (address position,) = PORTFOLIO_LENS.predictAddress(USER, SALT);

        (,,,,,, uint256 originationFee,,,,) = POOL.poolDataFor(WETH_POOL);
        uint256 fee = BP_BORROW_AMT.mulDiv(originationFee, 1e18);
        uint256 borrowAmtNetFees = BP_BORROW_AMT - fee;

        bytes memory data = abi.encodeWithSelector(SuperPool.deposit.selector, borrowAmtNetFees, position);

        Action[] memory actions = new Action[](6);
        actions[0] = ActionUtils.newPosition(USER, SALT);
        actions[1] = ActionUtils.deposit(address(seWETH), shares);
        actions[2] = ActionUtils.addToken(address(seWETH));
        actions[3] = ActionUtils.borrow(WETH_POOL, BP_BORROW_AMT);
        actions[4] = ActionUtils.approve(address(seWETH), address(WETH), borrowAmtNetFees);
        actions[5] = ActionUtils.exec(address(seWETH), 0, data);

        vm.startPrank(USER);
        seWETH.approve(address(POS_MGR), shares);
        POS_MGR.processBatch(position, actions);
        vm.stopPrank();
    }
}
