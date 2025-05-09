// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../BaseScript.s.sol";
import { RedstoneOracle } from "src/oracle/RedstoneOracle.sol";

contract DeployRedstoneOracle is BaseScript {
    event OracleDeployed(address oracle);

    RedstoneOracle oracle;

    address asset;
    string assetFeedIdString;
    string ethFeedIdString;
    uint256 assetFeedDecimals;
    uint256 ethFeedDecimals;

    function run() public {
        getParams();

        // Convert feed ID strings to bytes32
        bytes32 assetFeedId = stringToBytes32(assetFeedIdString);
        bytes32 ethFeedId = stringToBytes32(ethFeedIdString);

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new RedstoneOracle(asset, assetFeedId, ethFeedId, assetFeedDecimals, ethFeedDecimals);

        // Emit an event with the deployed address
        emit OracleDeployed(address(oracle));
    }

    function getParams() internal {
        asset = vm.parseJsonAddress(getConfig(), "$.DeployRedstoneOracle.asset");
        assetFeedIdString = vm.parseJsonString(getConfig(), "$.DeployRedstoneOracle.assetFeedId");
        ethFeedIdString = vm.parseJsonString(getConfig(), "$.DeployRedstoneOracle.ethFeedId");
        assetFeedDecimals = vm.parseJsonUint(getConfig(), "$.DeployRedstoneOracle.assetFeedDecimals");
        ethFeedDecimals = vm.parseJsonUint(getConfig(), "$.DeployRedstoneOracle.ethFeedDecimals");
    }

    // Helper function to convert string to bytes32
    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        // Convert string to bytes32
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) return 0x0;

        assembly {
            result := mload(add(source, 32))
        }
    }
}
