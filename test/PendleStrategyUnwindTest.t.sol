// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "src/Pool.sol";
import "src/Position.sol";
import "forge-std/Test.sol";
import "./utils/ActionUtils.sol";
import "src/PositionManager.sol";
import "src/lens/PortfolioLens.sol";
import "src/oracle/ChainlinkUsdOracle.sol";

contract PendleStrategyUnwindTest is Test {
    address constant USER = 0xFEf6c38FC24ecfB7ca39C8110A2cdf92b6de3139;
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDC_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address constant PENDLE_ROUTER = 0x888888888889758F76e7103c6CbF23ABbF58F946;

    uint constant POOL_ID = 115455159831402452207593952745663926536550346647623936005113871491318140345900;

    Pool constant POOL = Pool(0x9848e720CDba4364E9e1eb3000d87A7526832692);
    Position constant POSITION = Position(payable(0xbdc296998f88c264Ed17504B96D1368584F86B3d));
    IERC20 constant PT_USDE = IERC20(0xad853EB4fB3Fe4a66CdFCD7b75922a0494955292);
    PositionManager constant POS_MGR = PositionManager(0x78714046C08D05089EF2Fc79FB65cd5EeD08F30d);
    PortfolioLens constant PORTFOLIO_LENS = PortfolioLens(0xa64886401dCBdac66D1eeCDd77B743B05AD189ed);
    ChainlinkUsdOracle constant CL_USD_ORACLE = ChainlinkUsdOracle(0x74f88bAdab588F2997fEa8b2F05aC80d8B9307E2);

    function testGetPositionState() public view {
        PortfolioLens.PositionData memory positionData = PORTFOLIO_LENS.getPositionData(address(POSITION));
        console2.log("position: ", positionData.position);
        console2.log("owner: ", positionData.owner);
        console2.log("-x-x-x");
        console2.log("assets.length: ", positionData.assets.length);
        console2.log("assets[0].asset: ", positionData.assets[0].asset);
        console2.log("assets[0].amount: ", positionData.assets[0].amount);
        console2.log("assets[0].valueInEth: ", positionData.assets[0].valueInEth);
        console2.log("-x-x-x");
        console2.log("debts.length: ", positionData.debts.length);
        console2.log("debts.asset: ", positionData.debts[0].asset);
        console2.log("debts.amount: ", positionData.debts[0].amount);
        console2.log("debts.valueInEth: ", positionData.debts[0].valueInEth);
        assert(true);
    }

    function _getExecData() internal view {}
}
