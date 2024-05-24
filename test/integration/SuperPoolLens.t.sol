// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseTest.t.sol";
import {SuperPoolLens} from "src/lens/SuperPoolLens.sol";
import {FixedPriceOracle} from "src/oracle/FixedPriceOracle.sol";
import {console2} from "forge-std/console2.sol";

contract SuperPoolLensTests is BaseTest {
    SuperPool public superPool1;
    SuperPool public superPool2;
    address public feeTo = makeAddr("FeeTo");

    address[] public superPoolList;

    function setUp() public override {
        super.setUp();

        FixedPriceOracle oneEthOracle = new FixedPriceOracle(1e18);

        vm.startPrank(protocolOwner);
        riskEngine.setOracle(address(asset1), address(oneEthOracle)); // 1 asset1 = 1 eth
        riskEngine.setOracle(address(asset2), address(oneEthOracle)); // 1 asset2 = 1 eth
        vm.stopPrank();

        superPool1 = SuperPool(
            superPoolFactory.deploy(poolOwner, address(asset1), feeTo, 0.01 ether, 1_000_000 ether, "TEST1", "TEST1")
        );
        superPoolList.push(address(superPool1));

        superPool2 = SuperPool(
            superPoolFactory.deploy(poolOwner, address(asset2), feeTo, 0.01 ether, 1_000_000 ether, "TEST2", "TEST2")
        );
        superPoolList.push(address(superPool2));

        vm.startPrank(poolOwner);
        superPool1.setPoolCap(fixedRatePool, 50 ether);
        superPool1.setPoolCap(linearRatePool, 50 ether);
        superPool2.setPoolCap(alternateAssetPool, 50 ether);
        vm.stopPrank();

        vm.startPrank(user);
        asset1.mint(user, 50 ether);
        asset1.approve(address(superPool1), 50 ether);
        superPool1.deposit(50 ether, user);
        vm.stopPrank();

        vm.startPrank(user);
        asset2.mint(user, 50 ether);
        asset2.approve(address(superPool2), 50 ether);
        superPool2.deposit(50 ether, user);
        vm.stopPrank();

        vm.startPrank(user2);
        asset1.mint(user2, 50 ether);
        asset1.approve(address(superPool1), 50 ether);
        superPool1.deposit(50 ether, user2);
        vm.stopPrank();
    }

    function testInitSuperPool() public {
        SuperPoolLens testLens = new SuperPoolLens(address(pool), address(riskEngine));
        assertEq(address(testLens.POOL()), address(pool));
        assertEq(address(testLens.RISK_ENGINE()), address(riskEngine));
    }

    function testPoolInterestRate() public view {
        assertEq(superPoolLens.getPoolInterestRate(fixedRatePool), 1e18);
        assertEq(superPoolLens.getPoolInterestRate(linearRatePool), 1e18);
    }

    function testSuperPoolData() public view {
        SuperPoolLens.SuperPoolData memory superPoolData = superPoolLens.getSuperPoolData(address(superPool1));

        assertEq(superPoolData.name, "TEST1");
        assertEq(superPoolData.asset, address(asset1));
        assertEq(superPoolData.idleAssets, uint256(0));
        assertEq(superPoolData.totalAssets, uint256(100e18));
        assertEq(superPoolData.valueInEth, uint256(100e18));
        assertEq(superPoolData.interestRate, uint256(1e18));

        assertEq(superPoolData.deposits[0].asset, address(asset1));
        assertEq(superPoolData.deposits[0].poolId, uint256(fixedRatePool));
        assertEq(superPoolData.deposits[0].amount, uint256(50e18));
        assertEq(superPoolData.deposits[0].valueInEth, uint256(50e18));
        assertEq(superPoolData.deposits[0].interestRate, uint256(1e18));

        assertEq(superPoolData.deposits[1].asset, address(asset1));
        assertEq(superPoolData.deposits[1].poolId, uint256(linearRatePool));
        assertEq(superPoolData.deposits[1].amount, uint256(50e18));
        assertEq(superPoolData.deposits[1].valueInEth, uint256(50e18));
        assertEq(superPoolData.deposits[1].interestRate, uint256(1e18));
    }

    function testPoolDepositData() public view {
        SuperPoolLens.PoolDepositData memory poolDepositData =
            superPoolLens.getPoolDepositData(address(superPool1), fixedRatePool);

        assertEq(poolDepositData.asset, address(asset1));
        assertEq(poolDepositData.poolId, fixedRatePool);
        assertEq(poolDepositData.amount, uint256(50e18));
        assertEq(poolDepositData.valueInEth, uint256(50e18));
        assertEq(poolDepositData.interestRate, uint256(1e18));
    }

    function testSuperPoolDepositData() public view {
        SuperPoolLens.UserDepositData memory userDepositData =
            superPoolLens.getUserDepositData(user, address(superPool1));

        assertEq(userDepositData.owner, user);
        assertEq(userDepositData.asset, address(asset1));
        assertEq(userDepositData.superPool, address(superPool1));
        assertEq(userDepositData.amount, uint256(50e18));
        assertEq(userDepositData.valueInEth, uint256(50e18));
        assertEq(userDepositData.interestRate, uint256(1e18));
    }

    function testUserDepositData() public view {
        SuperPoolLens.UserMultiDepositData memory userMultiDepositData =
            superPoolLens.getUserMultiDepositData(user, superPoolList);

        assertEq(userMultiDepositData.owner, user);
        assertEq(userMultiDepositData.totalValueInEth, uint256(100e18));
        assertEq(userMultiDepositData.interestRate, uint256(1e18));

        assertEq(userMultiDepositData.deposits[0].owner, user);
        assertEq(userMultiDepositData.deposits[0].asset, address(asset1));
        assertEq(userMultiDepositData.deposits[0].superPool, address(superPool1));
        assertEq(userMultiDepositData.deposits[0].amount, uint256(50e18));
        assertEq(userMultiDepositData.deposits[0].valueInEth, uint256(50e18));
        assertEq(userMultiDepositData.deposits[0].interestRate, uint256(1e18));

        assertEq(userMultiDepositData.deposits[1].owner, user);
        assertEq(userMultiDepositData.deposits[1].asset, address(asset2));
        assertEq(userMultiDepositData.deposits[1].superPool, address(superPool2));
        assertEq(userMultiDepositData.deposits[1].amount, uint256(50e18));
        assertEq(userMultiDepositData.deposits[1].valueInEth, uint256(50e18));
        assertEq(userMultiDepositData.deposits[1].interestRate, uint256(1e18));
    }

    function testSuperPoolInterestRate() public view {
        assertEq(superPoolLens.getSuperPoolInterestRate(address(superPool1)), uint256(1e18));
        assertEq(superPoolLens.getSuperPoolInterestRate(address(superPool2)), uint256(1e18));
    }

    function testEmptySuperPoolInterestRate() public {
        SuperPool superPool3 = SuperPool(
            superPoolFactory.deploy(poolOwner, address(asset1), feeTo, 0.01 ether, 1_000_000 ether, "TEST3", "TEST3")
        );

        assertEq(superPoolLens.getSuperPoolInterestRate(address(superPool3)), 0);
    }
}
