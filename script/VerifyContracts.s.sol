// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { BaseScript } from "./BaseScript.s.sol";
import { Vm, VmSafe } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @title VerifyContracts
 * @notice Script to verify all contracts deployed by the DeploymentOrchestrator
 * Reads the most recent deployment log file and generates verification commands
 */
contract VerifyContracts is BaseScript {
    // Contract verification info
    struct ContractInfo {
        address addr;
        string contractPath;
        string constructorArgs;
        bool isProxy;
        address implementation;
    }

    // Mapping to store contract verification info
    mapping(string => ContractInfo) public contracts;
    string[] public contractNames;

    // Chain info
    uint256 public chainId;
    string public verifierUrl = "https://sourcify.parsec.finance/verify";

    function run() public {
        // Find most recent deployment log
        VmSafe.DirEntry[] memory dirEntries = vm.readDir(getLogPathBase());
        string memory latestLog = "";
        uint256 latestTimestamp = 0;

        for (uint256 i = 0; i < dirEntries.length; i++) {
            string memory fileName = dirEntries[i].path;

            // Extract just the filename from the path
            bytes memory fileNameBytes = bytes(fileName);
            uint256 fileNameLastSlashPos = 0;
            for (uint256 j = 0; j < fileNameBytes.length; j++) {
                if (fileNameBytes[j] == bytes1("/")) fileNameLastSlashPos = j + 1;
            }

            string memory fileNameOnly = "";
            if (fileNameLastSlashPos < fileNameBytes.length) {
                uint256 nameLength = fileNameBytes.length - fileNameLastSlashPos;
                bytes memory nameBytes = new bytes(nameLength);
                for (uint256 j = 0; j < nameLength; j++) {
                    nameBytes[j] = fileNameBytes[fileNameLastSlashPos + j];
                }
                fileNameOnly = string(nameBytes);
            }

            // Check if file contains DeploymentOrchestrator
            bool isDeploymentOrchestratorLog = false;
            bytes memory deploymentOrchestratorPrefix = bytes("DeploymentOrchestrator-");
            bytes memory fileNameOnlyBytes = bytes(fileNameOnly);

            if (fileNameOnlyBytes.length >= deploymentOrchestratorPrefix.length) {
                isDeploymentOrchestratorLog = true;
                for (uint256 j = 0; j < deploymentOrchestratorPrefix.length; j++) {
                    if (fileNameOnlyBytes[j] != deploymentOrchestratorPrefix[j]) {
                        isDeploymentOrchestratorLog = false;
                        break;
                    }
                }
            }

            if (isDeploymentOrchestratorLog) {
                // Extract timestamp from filename
                uint256 prefixLength = deploymentOrchestratorPrefix.length;
                uint256 suffixLength = 5; // ".json"
                uint256 timestampLength = fileNameOnlyBytes.length - prefixLength - suffixLength;

                bytes memory timestampBytes = new bytes(timestampLength);
                for (uint256 j = 0; j < timestampLength; j++) {
                    timestampBytes[j] = fileNameOnlyBytes[prefixLength + j];
                }

                string memory timestamp = string(timestampBytes);
                uint256 fileTimestamp = vm.parseUint(timestamp);

                if (fileTimestamp > latestTimestamp) {
                    latestTimestamp = fileTimestamp;
                    latestLog = fileName;
                }
            }
        }

        if (bytes(latestLog).length == 0) {
            console2.log("No deployment logs found");
            return;
        }

        // Extract just the filename part for logging
        string memory logFileName = "";
        bytes memory logPathBytes = bytes(latestLog);
        uint256 logPathLastSlashPos = 0;
        for (uint256 j = 0; j < logPathBytes.length; j++) {
            if (logPathBytes[j] == bytes1("/")) logPathLastSlashPos = j + 1;
        }

        if (logPathLastSlashPos < logPathBytes.length) {
            uint256 nameLength = logPathBytes.length - logPathLastSlashPos;
            bytes memory nameBytes = new bytes(nameLength);
            for (uint256 j = 0; j < nameLength; j++) {
                nameBytes[j] = logPathBytes[logPathLastSlashPos + j];
            }
            logFileName = string(nameBytes);
        }

        console2.log("Using log file:", logFileName);
        string memory logContent = vm.readFile(latestLog);

        // Read chain ID from log
        chainId = vm.parseJsonUint(logContent, "$.chainId");
        console2.log("Chain ID:", chainId);

        // Store all contract addresses and types
        _storeContractInfo(
            "registry",
            vm.parseJsonAddress(logContent, "$.registry"),
            "src/Registry.sol:Registry",
            "",
            false,
            address(0)
        );
        _storeContractInfo(
            "riskEngine",
            vm.parseJsonAddress(logContent, "$.riskEngine"),
            "src/RiskEngine.sol:RiskEngine",
            "",
            false,
            address(0)
        );
        _storeContractInfo(
            "riskModule",
            vm.parseJsonAddress(logContent, "$.riskModule"),
            "src/RiskModule.sol:RiskModule",
            "",
            false,
            address(0)
        );

        // Position Manager is a proxy with implementation
        address positionManager = vm.parseJsonAddress(logContent, "$.positionManager");
        address positionManagerImpl = vm.parseJsonAddress(logContent, "$.positionManagerImpl");
        _storeContractInfo(
            "positionManager", positionManager, "src/PositionManager.sol:PositionManager", "", true, positionManagerImpl
        );
        _storeContractInfo(
            "positionManagerImpl", positionManagerImpl, "src/PositionManager.sol:PositionManager", "", false, address(0)
        );

        // Pool is a proxy with implementation
        address pool = vm.parseJsonAddress(logContent, "$.pool");
        address poolImpl = vm.parseJsonAddress(logContent, "$.poolImpl");
        _storeContractInfo("pool", pool, "src/Pool.sol:Pool", "", true, poolImpl);
        _storeContractInfo("poolImpl", poolImpl, "src/Pool.sol:Pool", "", false, address(0));

        // Position Beacon
        _storeContractInfo(
            "positionBeacon",
            vm.parseJsonAddress(logContent, "$.positionBeacon"),
            "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol:UpgradeableBeacon",
            "",
            false,
            address(0)
        );

        // SuperPool Factory
        _storeContractInfo(
            "superPoolFactory",
            vm.parseJsonAddress(logContent, "$.superPoolFactory"),
            "src/SuperPoolFactory.sol:SuperPoolFactory",
            "",
            false,
            address(0)
        );

        // Lens contracts
        _storeContractInfo(
            "superPoolLens",
            vm.parseJsonAddress(logContent, "$.superPoolLens"),
            "src/lens/SuperPoolLens.sol:SuperPoolLens",
            "",
            false,
            address(0)
        );
        _storeContractInfo(
            "portfolioLens",
            vm.parseJsonAddress(logContent, "$.portfolioLens"),
            "src/lens/PortfolioLens.sol:PortfolioLens",
            "",
            false,
            address(0)
        );

        // IRM
        _storeContractInfo(
            "kinkedRateModel",
            vm.parseJsonAddress(logContent, "$.kinkedRateModel"),
            "src/irm/KinkedRateModel.sol:KinkedRateModel",
            "",
            false,
            address(0)
        );

        // SuperPool
        _storeContractInfo(
            "superPool",
            vm.parseJsonAddress(logContent, "$.superPool"),
            "src/SuperPool.sol:SuperPool",
            "",
            false,
            address(0)
        );

        // Generate verification script
        _generateVerificationScript();
    }

    function _storeContractInfo(
        string memory name,
        address addr,
        string memory contractPath,
        string memory constructorArgs,
        bool isProxy,
        address implementation
    )
        internal
    {
        ContractInfo storage info = contracts[name];
        info.addr = addr;
        info.contractPath = contractPath;
        info.constructorArgs = constructorArgs;
        info.isProxy = isProxy;
        info.implementation = implementation;

        contractNames.push(name);
    }

    function _generateVerificationScript() internal {
        // Start building verification script
        string memory verifyScript = "#!/bin/bash\n\n";
        verifyScript = string.concat(verifyScript, "# Auto-generated verification script for deployment\n");
        verifyScript = string.concat(verifyScript, "# Chain ID: ", vm.toString(chainId), "\n\n");

        // Add verification commands for each contract
        for (uint256 i = 0; i < contractNames.length; i++) {
            string memory name = contractNames[i];
            ContractInfo memory info = contracts[name];

            // Skip if address is zero
            if (info.addr == address(0)) continue;

            // Generate verification command
            string memory cmd = string.concat(
                'echo "Verifying ',
                name,
                " at ",
                vm.toString(info.addr),
                '"\n',
                "forge verify-contract ",
                vm.toString(info.addr),
                " ",
                info.contractPath,
                " \\\n",
                "  --chain-id ",
                vm.toString(chainId),
                " \\\n",
                "  --verifier sourcify \\\n",
                "  --verifier-url ",
                verifierUrl
            );

            // Add constructor args if provided
            if (bytes(info.constructorArgs).length > 0) {
                cmd = string.concat(cmd, " \\\n  --constructor-args ", info.constructorArgs);
            }

            // Add proxy implementation verification if it's a proxy
            if (info.isProxy && info.implementation != address(0)) {
                cmd = string.concat(
                    cmd,
                    "\n\n",
                    "# Verify implementation for ",
                    name,
                    "\n",
                    'echo "Verifying implementation for ',
                    name,
                    " at ",
                    vm.toString(info.implementation),
                    '"\n',
                    "forge verify-contract ",
                    vm.toString(info.implementation),
                    " ",
                    info.contractPath,
                    " \\\n",
                    "  --chain-id ",
                    vm.toString(chainId),
                    " \\\n",
                    "  --verifier sourcify \\\n",
                    "  --verifier-url ",
                    verifierUrl
                );
            }

            // Add to script with spacing
            verifyScript = string.concat(verifyScript, cmd, "\n\n");
        }

        // Add final echo
        verifyScript = string.concat(verifyScript, 'echo "Verification complete"\n');

        // Write script to file
        string memory scriptPath = string.concat("script/logs/verify-", vm.toString(block.timestamp), ".sh");
        vm.writeFile(scriptPath, verifyScript);

        // Make script executable
        vm.setEnv("SCRIPT_PATH", scriptPath);

        // Fix: Create a properly typed string array for vm.ffi
        string[] memory chmodCommand = new string[](3);
        chmodCommand[0] = "chmod";
        chmodCommand[1] = "+x";
        chmodCommand[2] = scriptPath;
        vm.ffi(chmodCommand);

        console2.log("Verification script generated at:", scriptPath);
        console2.log("Run the script to verify all contracts on chain ID:", chainId);
    }
}
