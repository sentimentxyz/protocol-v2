# DeFi Protocol Configuration and Deployment Guide

This guide explains how to configure and deploy the protocol using the DeploymentOrchestrator script, which automates the entire deployment workflow in a single transaction.

## Deployment Overview

The DeploymentOrchestrator handles the following steps in sequence:

1. Core protocol deployment
2. IRM (Interest Rate Model) deployment and registration
3. Oracle registration for assets
4. Pool initialization
5. LTV (Loan-to-Value) settings
6. SuperPool deployment
7. Pool cap setting
8. Asset whitelisting

## Prerequisites

- Properly set up Foundry environment
- Access to the target EVM blockchain (Hyperliquid mainnet or testnet)
- Private key with sufficient funds for deployment
- Configured JSON file with all deployment parameters

## Configuration Structure

Before deployment, you need to prepare a configuration file. By default, the script looks for:

```
config/<chain-id>/DeploymentOrchestrator.json
```

For Hyperliquid mainnet (Chain ID: 999), this would be:

```
config/999/DeploymentOrchestrator.json
```

The configuration file is structured in sections for better organization:

```json
{
  "DeploymentOrchestrator": {
    "protocolParams": { ... },
    "kinkedRateModelParams": { ... },
    "assetParams": { ... },
    "borrowPoolParams": { ... },
    "superPoolParams": { ... },
    "ltvSettings": { ... }
  }
}
```

### Protocol Parameters

```json
"protocolParams": {
  "owner": "0x0000000000000000000000000000000000000001",         // Protocol admin/owner address
  "proxyAdmin": "0x0000000000000000000000000000000000000002",    // Admin for upgradeable proxies
  "feeRecipient": "0x0000000000000000000000000000000000000003",  // Address that receives protocol fees
  "minLtv": "0.2e18",                                            // Min LTV: 0.2 (20%)
  "maxLtv": "0.8e18",                                            // Max LTV: 0.8 (80%)
  "minDebt": "0",                                                // Minimum debt amount
  "minBorrow": "0",                                              // Minimum borrow amount
  "liquidationFee": "0",                                         // Fee paid to liquidators
  "liquidationDiscount": "0.2e18",                               // Discount for liquidators (20%)
  "badDebtLiquidationDiscount": "0.01e18",                       // Bad debt liquidation discount (1%)
  "defaultInterestFee": "0",                                     // Default interest fee
  "defaultOriginationFee": "0"                                   // Default origination fee
}
```

### Kinked Rate Model Parameters

```json
"kinkedRateModelParams": {
  "minRate": "0.01e18",                                          // Min interest rate (1%)
  "slope1": "0.1e18",                                            // Interest rate slope before optimal util (10%)
  "slope2": "1e18",                                              // Interest rate slope after optimal util (100%)
  "optimalUtil": "0.8e18"                                        // Optimal utilization point (80%)
}
```

### Asset Parameters

```json
"assetParams": {
  "borrowAsset": "0x5555555555555555555555555555555555555555",    // Address of borrowable token
  "borrowAssetOracle": "0x712047cC3e4b0023Fccc09Ae412648CF23C65ed3", // Oracle for borrowable token
  "collateralAsset": "0x94e8396e0869c9F2200760aF0621aFd240E1CF38", // Address of collateral token
  "collateralAssetOracle": "0x619b82845177a163681b08e7684a2bb968011c68" // Oracle for collateral token
}
```

### Borrow Pool Parameters

```json
"borrowPoolParams": {
  "borrowAssetPoolCap": "max",                                   // Max deposits (use "max" for unlimited)
  "borrowAssetBorrowCap": "max",                                 // Max borrows (use "max" for unlimited)
  "borrowAssetInitialDeposit": "1e18"                            // Initial deposit amount (1 token)
}
```

### SuperPool Parameters

```json
"superPoolParams": {
  "superPoolCap": "max",                                         // Max deposits in SuperPool (use "max" for unlimited)
  "superPoolFee": "0",                                           // SuperPool fee
  "superPoolInitialDeposit": "1e18",                             // Initial deposit amount (1 token)
  "superPoolName": "Example SuperPool",                          // Name of the SuperPool token
  "superPoolSymbol": "ESP"                                       // Symbol of the SuperPool token
}
```

### LTV Settings

```json
"ltvSettings": {
  "collateralLtv": "0.8e18"                                      // LTV for collateral asset (80%)
}
```

### Scientific Notation Format

This configuration uses a simplified scientific notation for easy readability:

- `0.2e18` represents 0.2 \* 10^18 = 200,000,000,000,000,000
- `1e18` represents 1 \* 10^18 = 1,000,000,000,000,000,000
- `0.01e18` represents 0.01 \* 10^18 = 10,000,000,000,000,000

The orchestrator script will convert these values to the full integer representation required by the smart contracts.

### Special Values

For unlimited caps, use the keyword `"max"` instead of the full uint256 maximum value. The orchestrator will automatically replace this with the correct maximum value.

## Running the Deployment

Once your configuration file is ready, you can run the DeploymentOrchestrator with the following command:

```bash
# For testnet (development environments)
forge script DeploymentOrchestrator --rpc-url https://rpc.hyperliquid-testnet.xyz/evm --broadcast

# For mainnet (production deployments)
forge script DeploymentOrchestrator --rpc-url https://rpc.hyperliquid.xyz/evm --broadcast --slow
```

Make sure to set the following environment variables:

```bash
export PRIVATE_KEY=your_private_key
export SCRIPT_CONFIG=DeploymentOrchestrator.json
```

### Understanding the `--slow` Flag

The `--slow` flag is critical for complex deployments with multiple interdependent contracts:

- It ensures each transaction is sent only after the previous one has been confirmed and succeeded
- This prevents nonce issues and confirms that contract dependencies are properly established
- Without this flag, transactions may be processed out of order, which can cause deployment failures

If you encounter issues deploying multiple contracts without the `--slow` flag, consider these alternatives:

1. **Using a smaller batch size**:
   ```bash
   forge script DeploymentOrchestrator --rpc-url https://rpc.hyperliquid.xyz/evm --broadcast --batch-size 1
   ```
2. **Setting a higher gas price** to help ensure transactions are processed in order:
   ```bash
   forge script DeploymentOrchestrator --rpc-url https://rpc.hyperliquid.xyz/evm --broadcast --with-gas-price 10gwei
   ```

For production deployments on Hyperliquid mainnet, we recommend using the `--slow` flag for maximum reliability.

## Deployment Output

After a successful deployment, the script will:

1. Print logs for each step in the console
2. Generate a detailed JSON log file with all deployed contract addresses and configuration parameters in the `script/logs/` directory

The log file name will be in the format: `DeploymentOrchestrator-<timestamp>.json`

## Verification

There are two types of verification you should perform after deployment:

### 1. Deployment Verification

To verify the deployment was successful, you can use the VerifyDeployment script:

```bash
# For testnet
forge script VerifyDeployment --rpc-url https://rpc.hyperliquid-testnet.xyz/evm

# For mainnet
forge script VerifyDeployment --rpc-url https://rpc.hyperliquid.xyz/evm
```

This script will:

1. Find the most recent deployment log file
2. Load all contract addresses from the log
3. Check that all contracts were deployed correctly
4. Verify all configuration settings
5. Produce a detailed report of the deployment status

### 2. Contract Source Code Verification

To verify all contract source code on the blockchain explorer, use the VerifyContracts script:

```bash
# Generate the verification script
forge script VerifyContracts

# Run the generated verification script
./script/logs/verify-<timestamp>.sh
```

The VerifyContracts script:

1. Reads the latest deployment log
2. Generates a shell script with verification commands for each deployed contract
3. Makes the script executable

The generated script will verify each contract using Forge's verification capabilities with Sourcify:

```bash
forge verify-contract <contract-address> <contract-path>:<contract-name> \
  --chain-id 999 \
  --verifier sourcify \
  --verifier-url https://sourcify.parsec.finance/verify
```

For proxies, it will verify both the proxy and implementation contracts.

## Testing Approaches

Before deploying to mainnet, use these testing approaches:

### 1. Local Testing with Anvil

The safest way to test the orchestrator is using a local Anvil instance:

```bash
# Start a local Anvil instance
anvil --fork-url https://rpc.hyperliquid-testnet.xyz/evm

# In a new terminal, run the orchestrator against the local instance
forge script DeploymentOrchestrator --rpc-url http://localhost:8545 --broadcast
```

### 2. Testnet Deployment

Once you've validated on a local fork, try a full testnet deployment:

```bash
# Deploy to Hyperliquid testnet
forge script DeploymentOrchestrator --rpc-url https://rpc.hyperliquid-testnet.xyz/evm --broadcast
```
