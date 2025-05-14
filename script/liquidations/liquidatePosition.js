#!/usr/bin/env node

/**
 * Liquidate Position Script
 * 
 * This script helps liquidate positions by running the LiquidatePosition forge script.
 * 
 * How to run:
 * 1. Make sure ethers package is installed: npm install ethers
 * 2. Execute the script directly: ./script/liquidations/liquidatePosition.js
 *    or with node: node script/liquidations/liquidatePosition.js
 * 
 * The script will prompt for:
 * - Your private key (to sign the transaction)
 * - Position address to liquidate
 * - Liquidation type (normal or bad debt)
 */

const { execSync } = require('child_process');
const readline = require('readline');
const { ethers } = require('ethers');
const fs = require('fs');

// Create readline interface
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

// Function to prompt for input
function prompt(question) {
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      resolve(answer);
    });
  });
}

async function main() {
  try {
    console.log('=== Liquidate Position Script ===');
    
    // Prompt for private key
    const privateKey = await prompt('Enter your private key: ');
    
    if (!privateKey || !privateKey.startsWith('0x') || privateKey.length !== 66) {
      console.error('Error: Invalid private key format');
      process.exit(1);
    }
    
    // Derive wallet address from private key
    const wallet = new ethers.Wallet(privateKey);
    const senderAddress = wallet.address;
    
    console.log(`Derived sender address: ${senderAddress}`);
    
    // Prompt for position address to liquidate
    const positionAddress = await prompt('Enter the position address to liquidate: ');
    
    if (!positionAddress || !positionAddress.startsWith('0x')) {
      console.error('Error: Invalid position address format');
      process.exit(1);
    }
    
    // Prompt for liquidation type
    const liquidationType = await prompt('Enter liquidation type (1 for normal, 2 for bad debt): ');
    
    let sigFunction;
    if (liquidationType === '1') {
      sigFunction = 'run(address)';
      console.log('Selected: Normal liquidation');
    } else if (liquidationType === '2') {
      sigFunction = 'runBadDebt(address)';
      console.log('Selected: Bad debt liquidation');
    } else {
      console.error('Error: Invalid liquidation type. Please enter 1 or 2.');
      process.exit(1);
    }
    
    // Hardcode RPC URL
    const rpcUrl = 'https://rpc.hyperliquid.xyz/evm';
    
    console.log('\nExecuting forge script with the following parameters:');
    console.log(`- Position address: ${positionAddress}`);
    console.log(`- Sender address: ${senderAddress}`);
    console.log(`- RPC URL: ${rpcUrl}`);
    console.log(`- Function signature: ${sigFunction}`);
    
    // Build the forge script command
    const command = `forge script script/liquidations/LiquidatePosition.s.sol:LiquidatePosition \
--rpc-url ${rpcUrl} \
--private-key ${privateKey} \
--broadcast -vvvv \
--sig "${sigFunction}" ${positionAddress} \
--sender ${senderAddress}`;
    
    console.log('\nRunning forge script...');
    
    // Execute the command
    const output = execSync(command, { stdio: 'inherit' });
    
  } catch (error) {
    console.error('Error executing script:', error.message);
  } finally {
    rl.close();
  }
}

main(); 