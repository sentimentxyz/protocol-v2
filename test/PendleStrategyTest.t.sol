// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "src/Pool.sol";
import "forge-std/Test.sol";
import "./utils/ActionUtils.sol";
import "src/PositionManager.sol";
import "src/lens/PortfolioLens.sol";
import "src/oracle/ChainlinkUsdOracle.sol";

contract PendleStrategyTest is Test {
    address constant USER = 0xFEf6c38FC24ecfB7ca39C8110A2cdf92b6de3139;
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDC_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address constant PENDLE_ROUTER = 0x888888888889758F76e7103c6CbF23ABbF58F946;

    bytes32 constant SALT = 0xc8ee9b48f1f337183999968f54093832bca4f00182f61cadbf91a4c35a8871ef;

    uint constant BOR_AMT = 30e6;
    uint constant DEP_AMT = 40e18;
    uint constant POOL_ID = 115455159831402452207593952745663926536550346647623936005113871491318140345900;

    Pool constant POOL = Pool(0x9848e720CDba4364E9e1eb3000d87A7526832692);
    IERC20 constant PT_USDE = IERC20(0xad853EB4fB3Fe4a66CdFCD7b75922a0494955292);
    PositionManager constant POS_MGR = PositionManager(0x78714046C08D05089EF2Fc79FB65cd5EeD08F30d);
    PortfolioLens constant PORTFOLIO_LENS = PortfolioLens(0xa64886401dCBdac66D1eeCDd77B743B05AD189ed);
    ChainlinkUsdOracle constant CL_USD_ORACLE = ChainlinkUsdOracle(0x74f88bAdab588F2997fEa8b2F05aC80d8B9307E2);

    function testGetValueInEth() public view {
        address asset = USDC;
        uint amt = 3e7;

        uint stalePriceThreshold = CL_USD_ORACLE.stalePriceThresholdFor(USDC_FEED);
        console2.log("asset: ", asset);
        console2.log("stalePriceThreshold", stalePriceThreshold); 

        uint value = CL_USD_ORACLE.getValueInEth(asset, amt);
        console2.log("amt: ", amt);
        console2.log("value: ", value);
    }


    function testCreatePosition() public returns (address position) {
        (position,) = PORTFOLIO_LENS.predictAddress(USER, SALT);
        console2.log("Position: ", position);

        Action memory action = ActionUtils.newPosition(USER, SALT);

        vm.prank(USER);
        POS_MGR.process(position, action);
    }

    function testDeposit() public returns (address) {
        address position = testCreatePosition();

        Action[] memory actions = new Action[](2);
        actions[0] = ActionUtils.deposit(address(PT_USDE), DEP_AMT);
        actions[1] = ActionUtils.addToken(address(PT_USDE));

        vm.startPrank(USER);
        PT_USDE.approve(address(POS_MGR), DEP_AMT);
        POS_MGR.processBatch(position, actions);
        vm.stopPrank();

        return position;
    }

    function testBorrowAndExec() public {
        address position = testDeposit();
        bytes memory data = _getExecData(position, BOR_AMT);

        Action[] memory actions = new Action[](3);
        actions[0] = ActionUtils.borrow(POOL_ID, BOR_AMT);
        actions[1] = ActionUtils.approve(PENDLE_ROUTER, USDC, BOR_AMT);
        actions[2] = ActionUtils.exec(PENDLE_ROUTER, 0, data);

        vm.prank(USER);
        POS_MGR.processBatch(position, actions);
    }

    function _getExecData(address position, uint amt) internal returns (bytes memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "bash" ;
        inputs[1] = "script/getPendleExecData.sh";
        inputs[2] = vm.toString(position);
        inputs[3] = vm.toString(amt);

        bytes memory data = vm.ffi(inputs);
        return data;
    }
}
