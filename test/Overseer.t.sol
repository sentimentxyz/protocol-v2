// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { StdStorage, stdStorage } from "lib/forge-std/src/StdStorage.sol";

interface IOverseer {
    function burnAndRedeemIfPossible(address to, uint256 amount, string memory code) external;
    function burn(address to, uint256 amount) external;
    function redeem(uint256 burnId) external;
}
contract OverseerTest is Test {
    IOverseer overseer = IOverseer(0xB96f07367e69e86d6e9C3F29215885104813eeAE);
    IERC20 wstHype = IERC20(0x94e8396e0869c9F2200760aF0621aFd240E1CF38);
    IERC20 stHype = IERC20(0xfFaa4a3D97fE9107Cef8a3F48c069F577Ff76cC1);

    address user = 0xB290f2F3FAd4E540D0550985951Cdad2711ac34A; 

    address position = 0x68cf011c5bbd4A5498Bc1a05F30f20402f49f686;

    function setUp() public {
        vm.createSelectFork("https://rpc.hyperliquid.xyz/evm");
    }

    function testUnstake() public {
        vm.startPrank(position);
        
        console2.log("wstHype balance", wstHype.balanceOf(position));
        console2.log("Hype balance", position.balance);

        //wstHype.approve(address(overseer), 1e18);
        console2.log("approval", wstHype.allowance(position, address(overseer)), stHype.allowance(position, address(overseer)));

        overseer.burnAndRedeemIfPossible(position, 1e18, "");

        console2.log("wstHype balance", wstHype.balanceOf(position));
        console2.log("Hype balance", position.balance);

        vm.stopPrank();
    }
}
