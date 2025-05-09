// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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

    // Track addresses to avoid duplications
    mapping(address => bool) private _addressesProcessed;

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
        // Try to get positionManagerImpl, or use a placeholder if not available
        address positionManagerImpl;
        try vm.parseJsonAddress(logContent, "$.positionManagerImpl") returns (address addr) {
            positionManagerImpl = addr;
        } catch {
            // If positionManagerImpl is not in the log, use a placeholder
            positionManagerImpl = 0x4AEa23D94197414df05D544647B4EE6F194458Fe; // Set this to the actual address if known
            console2.log("Warning: positionManagerImpl not found in log, using hardcoded address:", positionManagerImpl);
        }
        _storeContractInfo(
            "positionManager", positionManager, "src/PositionManager.sol:PositionManager", "", true, positionManagerImpl
        );

        // Pool is a proxy with implementation
        address pool = vm.parseJsonAddress(logContent, "$.pool");
        // Try to get poolImpl, or use a placeholder if not available
        address poolImpl;
        try vm.parseJsonAddress(logContent, "$.poolImpl") returns (address addr) {
            poolImpl = addr;
        } catch {
            // If poolImpl is not in the log, use a placeholder
            poolImpl = 0x90AE6cD9Bd8fA354A94AFa256074bf1E3009F73F; // Set this to the actual address if known
            console2.log("Warning: poolImpl not found in log, using hardcoded address:", poolImpl);
        }
        _storeContractInfo("pool", pool, "src/Pool.sol:Pool", "", true, poolImpl);

        // Position Beacon
        _storeContractInfo(
            "positionBeacon",
            vm.parseJsonAddress(logContent, "$.positionBeacon"),
            "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol:UpgradeableBeacon",
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
        // Skip if address is zero
        if (addr == address(0)) return;

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

        // Add utility functions
        verifyScript = string.concat(
            verifyScript,
            "# Function to verify a contract with timeout\n",
            "verify_contract() {\n",
            '  local address="$1"\n',
            '  local contract="$2"\n',
            '  local name="$3"\n',
            '  local args="$4"\n\n',
            '  echo "==================================================="\n',
            '  echo "Verifying $name at $address"\n',
            '  echo "==================================================="\n\n',
            "  # Simple timeout mechanism - kill after 30 seconds\n",
            "  timeout_cmd() {\n",
            "    ( $@ ) & pid=$!\n",
            "    ( sleep 30 && kill -9 $pid 2>/dev/null ) & watcher=$!\n",
            "    wait $pid 2>/dev/null\n",
            "    status=$?\n",
            "    kill -9 $watcher 2>/dev/null\n",
            "    return $status\n",
            "  }\n\n",
            "  # Try to verify, but don't worry if it fails\n",
            '  cmd="forge verify-contract $address $contract --chain-id ',
            vm.toString(chainId),
            " --verifier sourcify --verifier-url ",
            verifierUrl,
            '"\n',
            '  if [ -n "$args" ]; then\n',
            '    cmd="$cmd --constructor-args $args"\n',
            "  fi\n\n",
            "  # Run with timeout\n",
            '  timeout_cmd $cmd || echo "Verification failed or timed out, continuing..."\n',
            '  echo ""\n',
            "}\n\n"
        );

        // Add verification commands for each contract
        for (uint256 i = 0; i < contractNames.length; i++) {
            string memory name = contractNames[i];
            ContractInfo memory info = contracts[name];

            // Skip if address is zero
            if (info.addr == address(0) || _addressesProcessed[info.addr]) continue;

            // Generate verification command
            string memory cmd = string.concat(
                "verify_contract ",
                vm.toString(info.addr),
                " ",
                info.contractPath,
                ' "',
                name,
                '" "',
                info.constructorArgs,
                '"\n'
            );

            // Add to script with spacing
            verifyScript = string.concat(verifyScript, cmd);

            // Mark this address as processed
            _addressesProcessed[info.addr] = true;

            // Add proxy implementation verification if it's a proxy
            if (info.isProxy && info.implementation != address(0) && !_addressesProcessed[info.implementation]) {
                cmd = string.concat(
                    "# Implementation for ",
                    name,
                    "\n",
                    "verify_contract ",
                    vm.toString(info.implementation),
                    " ",
                    info.contractPath,
                    ' "',
                    name,
                    ' implementation" "',
                    info.constructorArgs,
                    '"\n'
                );

                // Add to script
                verifyScript = string.concat(verifyScript, cmd);

                // Mark implementation as processed
                _addressesProcessed[info.implementation] = true;
            }
        }

        // Add final echo
        verifyScript = string.concat(verifyScript, '\necho "Verification script completed"\n');

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
