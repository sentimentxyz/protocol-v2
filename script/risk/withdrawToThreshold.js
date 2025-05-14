// withdrawToThreshold.js
// Script to withdraw assets from a position to bring health factor close to 1e18
//
// USAGE:
// - Run script: node script/risk/withdrawToThreshold.js
// - Specify custom amount: node script/risk/withdrawToThreshold.js --amount=0.5
// - Non-interactive mode: node script/risk/withdrawToThreshold.js --non-interactive
//   (requires PRIVATE_KEY environment variable)
//
// This script:
// 1. Calculates the maximum withdrawable amount considering maximum allowed LTV
// 2. For first attempt, uses the calculated safe amount
// 3. On successful withdrawal, recalculates optimal withdrawal amount
// 4. On failed withdrawal, tries 50% less than the failed amount
// 5. Continues until health factor is close to 1.0 or max attempts reached
//
// IMPORTANT: The withdrawable amount is limited by the max LTV constraint.
// LTV (Loan-to-Value) is calculated as debt/assets. As you withdraw assets,
// the LTV increases. The system will not allow LTV to exceed the max allowed value.
//
// The script will prompt for your private key unless you set the PRIVATE_KEY
// environment variable or use the --non-interactive flag.

const { ethers } = require('ethers');
const readline = require('readline');

// Process command line arguments
const args = process.argv.slice(2);
const NON_INTERACTIVE = args.includes('--non-interactive') || args.includes('-n');
const CUSTOM_AMOUNT = args.find(arg => arg.startsWith('--amount=') || arg.startsWith('-a='));
let CUSTOM_AMOUNT_VALUE = null;
if (CUSTOM_AMOUNT) {
  CUSTOM_AMOUNT_VALUE = CUSTOM_AMOUNT.split('=')[1];
}

// Constants
const POSITION_ADDRESS = '0xe3e83aF7B6B4A97d492B46F246Ac18648D1212Ce';
const TARGET_HEALTH_FACTOR = ethers.utils.parseUnits('1.0', 18); // Exactly 1e18
const THRESHOLD_PRECISION = ethers.utils.parseUnits('0.0000000001', 18); // Very small difference threshold
const POSITION_MANAGER_ADDRESS = '0xE019Ce6e80dFe505bca229752A1ad727E14085a4'; // HyperEVM Mainnet
const RISK_ENGINE_ADDRESS = '0xd22dE451Ba71fA6F06C65962649ba4E2Aea10863'; // HyperEVM Mainnet
const RPC_URL = 'https://rpc.hyperliquid.xyz/evm';
const MAX_ITERATIONS = 20; // Maximum number of successful withdrawal iterations
// Default pool ID in case we can't get it from the position (fallback)
const DEFAULT_POOL_ID = '24340067792848736884157565898336136257613434225645880261054440301452940585526';
// Default LTV in case we can't get it from the contract (fallback)
const DEFAULT_MAX_LTV = ethers.utils.parseUnits('0.9', 18); // 90%
// Minimum withdrawal amount to use when there's no previous valid amount
const MIN_FALLBACK_PERCENTAGE = ethers.utils.parseUnits('0.001', 18); // 0.1% of balance

// ABIs - Add the relevant parts only
const PositionABI = [
  "function getPositionAssets() external view returns (address[] memory)",
  "function balanceOf(address account) external view returns (uint256)",
  "function getDebtPools() external view returns (uint256[] memory)"
];

const RiskEngineABI = [
  "function getPositionHealthFactor(address position) external view returns (uint256)",
  "function getValueInEth(address asset, uint256 amount) external view returns (uint256)",
  "function getRiskData(address position) external view returns (uint256 totalAssetValue, uint256 totalDebtValue, uint256 minReqAssetValue)",
  "function ltvFor(uint256 poolId, address asset) external view returns (uint256)"
];

const PositionManagerABI = [
  "function process(address position, tuple(uint8 op, bytes data) action) external",
  "function owner() external view returns (address)"
];

const ERC20ABI = [
  "function balanceOf(address owner) external view returns (uint256)",
  "function decimals() external view returns (uint8)",
  "function symbol() external view returns (string)"
];

// Operation enum from PositionManager contract
const Operation = {
  NewPosition: 0,
  Exec: 1,        
  Deposit: 2,     
  Transfer: 3,    
  Approve: 4,     
  Repay: 5,       
  Borrow: 6,      
  AddToken: 7,    
  RemoveToken: 8  
};

// Function to get private key from user input with hidden input
function getPrivateKey() {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
      terminal: true
    });
    
    // Create a mutable variable to store the key
    let privateKey = '';
    
    // Override the _writeToOutput method to mask input
    const originalWrite = rl._writeToOutput;
    rl._writeToOutput = function(stringToWrite) {
      if (stringToWrite.includes(privateKey) && privateKey.length > 0) {
        // Replace the actual private key with asterisks in the output
        const maskedString = stringToWrite.replace(privateKey, '*'.repeat(privateKey.length));
        originalWrite.call(this, maskedString);
      } else {
        originalWrite.call(this, stringToWrite);
      }
    };
    
    process.stdout.write('Enter your private key: ');
    
    // Use raw mode to catch each keypress
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdin.setEncoding('utf8');
    
    process.stdin.on('data', (key) => {
      const str = String(key);
      
      // Ctrl+C or Ctrl+D
      if (str === '\u0003' || str === '\u0004') {
        process.stdin.setRawMode(false);
        process.stdin.pause();
        console.log('\nOperation canceled');
        resolve('');
        return;
      }
      
      // Enter key
      if (str === '\r' || str === '\n') {
        process.stdout.write('\n');
        process.stdin.setRawMode(false);
        process.stdin.pause();
        process.stdin.removeAllListeners('data');
        rl.close();
        resolve(privateKey.trim());
        return;
      }
      
      // Backspace
      if (str === '\u007F' || str === '\b') {
        if (privateKey.length > 0) {
          privateKey = privateKey.slice(0, -1);
          process.stdout.write('\b \b'); // Erase the last character
        }
        return;
      }
      
      // Add character to private key and display an asterisk
      privateKey += str;
      process.stdout.write('*');
    });
  });
}

// Main function
async function main() {
  console.log("Script started");
  console.log(`Mode: ${NON_INTERACTIVE ? 'Non-interactive' : 'Interactive'}`);
  if (CUSTOM_AMOUNT_VALUE) {
    console.log(`Custom amount specified: ${CUSTOM_AMOUNT_VALUE}`);
  }
  
  // Get private key from environment variable or user input
  const privateKey = NON_INTERACTIVE && process.env.PRIVATE_KEY ? 
    process.env.PRIVATE_KEY : await getPrivateKey();
  if (!privateKey) {
    console.error("Private key is required");
    process.exit(1);
  }
  
  // Set up provider and signer
  const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(privateKey, provider);
  
  console.log(`Connected with address: ${wallet.address}`);
  console.log(`Position: ${POSITION_ADDRESS}`);
  console.log(`Target health factor: ${ethers.utils.formatUnits(TARGET_HEALTH_FACTOR, 18)}`);
  
  // Connect to contracts
  const position = new ethers.Contract(POSITION_ADDRESS, PositionABI, provider);
  const riskEngine = new ethers.Contract(RISK_ENGINE_ADDRESS, RiskEngineABI, provider);
  const positionManager = new ethers.Contract(POSITION_MANAGER_ADDRESS, PositionManagerABI, wallet);
  
  // Get position owner - assuming it's the wallet address
  const positionOwner = wallet.address;
  console.log(`Position owner: ${positionOwner}`);
  
  // Get positionManager owner to check permissions
  const pmOwner = await positionManager.owner();
  console.log(`PositionManager owner: ${pmOwner}`);
  
  try {
    // Print debt pools if any
    const debtPools = await position.getDebtPools();
    console.log(`Position debt pools: ${debtPools.length > 0 ? debtPools.join(", ") : "None"}`);
    
    // Get pool ID to use for ltvFor query - use first debt pool or default
    const poolId = debtPools.length > 0 ? debtPools[0] : DEFAULT_POOL_ID;
    console.log(`Using pool ID for LTV query: ${poolId}`);
    
    // Get assets and their balances for the position
    const assets = await position.getPositionAssets();
    const assetDetails = await getAssetDetails(assets, position, riskEngine, provider);
    
    if (assetDetails.length === 0) {
      console.log("No suitable assets found for withdrawal");
      return;
    }
    
    // Sort assets by value (highest first)
    assetDetails.sort((a, b) => b.valueInEth.gt(a.valueInEth) ? 1 : -1);
    
    // Get the asset with the highest value
    const primaryAsset = assetDetails[0];
    console.log(`Primary asset for withdrawals: ${primaryAsset.symbol} (${primaryAsset.address})`);
    console.log(`Asset balance: ${ethers.utils.formatUnits(primaryAsset.balance, primaryAsset.decimals)} ${primaryAsset.symbol}`);
    console.log(`Asset value: ${ethers.utils.formatEther(primaryAsset.valueInEth)} ETH`);
    
    // Get the real max LTV from the contract for the specific pool and asset we're withdrawing
    console.log(`Fetching max LTV from RiskEngine for pool ${poolId} and asset ${primaryAsset.address}...`);
    let MAX_LTV;
    try {
      MAX_LTV = await riskEngine.ltvFor(poolId, primaryAsset.address);
      console.log(`Max LTV from contract: ${ethers.utils.formatUnits(MAX_LTV, 18)} (${ethers.utils.formatUnits(MAX_LTV, 16)}%)`);
    } catch (error) {
      console.error(`Error fetching LTV from contract: ${error.message}`);
      console.log(`Falling back to default ${ethers.utils.formatUnits(DEFAULT_MAX_LTV, 16)}% LTV`);
      MAX_LTV = DEFAULT_MAX_LTV; // Default if fetching fails
    }
    
    // Store latest successful withdrawal amount
    let lastSuccessfulWithdrawal = null;
    
    // Calculate initial withdrawal amount based on health factor formula
    console.log("\n--- Initial Health Factor Based Calculation ---");

    // Get position health factor and risk data
    let currentHealthFactor = await riskEngine.getPositionHealthFactor(POSITION_ADDRESS);
    const riskData = await riskEngine.getRiskData(POSITION_ADDRESS);
    const totalAssetValue = riskData.totalAssetValue;
    const totalDebtValue = riskData.totalDebtValue;

    // Log current values
    console.log(`Current health factor: ${ethers.utils.formatUnits(currentHealthFactor, 18)}`);
    console.log(`Total asset value: ${ethers.utils.formatEther(totalAssetValue)} ETH`);
    console.log(`Total debt value: ${ethers.utils.formatEther(totalDebtValue)} ETH`);
    
    // Calculate current LTV
    const currentLTV = totalDebtValue.mul(ethers.utils.parseUnits('1', 18)).div(totalAssetValue);
    console.log(`Current LTV: ${ethers.utils.formatUnits(currentLTV, 16)}%`);
    console.log(`Max LTV allowed: ${ethers.utils.formatUnits(MAX_LTV, 16)}%`);
    
    // Check if current LTV is already at or above the max LTV
    if (currentLTV.gte(MAX_LTV)) {
      console.log(`⚠️ WARNING: Current LTV (${ethers.utils.formatUnits(currentLTV, 16)}%) is already at or above the maximum allowed LTV (${ethers.utils.formatUnits(MAX_LTV, 16)}%).`);
      console.log(`⚠️ You cannot withdraw any assets without first repaying some debt or adding more collateral.`);
      console.log("Continuing anyway with small withdrawals, but transactions will likely fail.");
    }

    // If health factor is already at or below target, warn but continue
    if (currentHealthFactor.lte(TARGET_HEALTH_FACTOR)) {
      console.log("Health factor already at or below target. Withdrawals may fail, but continuing anyway.");
    }

    // Properly calculate withdrawable amount from first principles
    // If we have:
    // Current assets = A
    // Current debt = D
    // Maximum LTV = L (90%)
    //
    // To keep LTV at or below L after withdrawal, we must ensure:
    // D / (A - W) ≤ L
    // D ≤ L * (A - W)
    // D / L ≤ A - W
    // W ≤ A - D / L
    // 
    // Therefore, maximum withdrawal amount:
    // W = A - D / L

    let withdrawableValueInEth;

    if (currentHealthFactor.gt(TARGET_HEALTH_FACTOR)) {
      console.log(`\n--- LTV-Based Calculation ---`);
      console.log(`- Current health factor: ${ethers.utils.formatUnits(currentHealthFactor, 18)}`);
      console.log(`- Current LTV: ${ethers.utils.formatUnits(currentLTV, 16)}%`);
      console.log(`- Total asset value: ${ethers.utils.formatEther(totalAssetValue)} ETH`);
      console.log(`- Total debt value: ${ethers.utils.formatEther(totalDebtValue)} ETH`);
      
      // Calculate withdrawable amount that keeps LTV at maximum allowed value
      // Formula: W = A - D / L, where
      // W = withdrawable amount
      // A = total assets
      // D = total debt
      // L = max LTV
      withdrawableValueInEth = totalAssetValue.sub(
        totalDebtValue.mul(ethers.utils.parseUnits('1', 18)).div(MAX_LTV)
      );
      
      console.log(`- Withdrawable value (LTV-based): ${ethers.utils.formatEther(withdrawableValueInEth)} ETH`);
      
      // If the withdrawable amount is negative, set it to zero
      if (withdrawableValueInEth.lt(0)) {
        console.log(`- Calculated withdrawable amount is negative, setting to zero`);
        withdrawableValueInEth = ethers.BigNumber.from(0);
      }
      
      // Apply a small safety factor to account for price movements
      const WEI = ethers.BigNumber.from(10).pow(18);
      const SAFETY_FACTOR = ethers.BigNumber.from(999).mul(WEI).div(1000); // 99.9% to be very safe
      withdrawableValueInEth = withdrawableValueInEth.mul(SAFETY_FACTOR).div(WEI);
      
      console.log(`- With 99.9% safety factor: ${ethers.utils.formatEther(withdrawableValueInEth)} ETH`);
      console.log(`- Using full calculated amount for first attempt (no arbitrary reductions)`);
    } else {
      // If health factor <= target, no withdrawable amount but still try with a small amount
      withdrawableValueInEth = ethers.BigNumber.from(0);
      console.log(`- No withdrawable amount as health factor is already at or below target. Will try with minimum amount.`);
    }

    console.log(`Final calculated withdrawable value: ${ethers.utils.formatEther(withdrawableValueInEth)} ETH`);

    // Calculate the token amount to withdraw based on ETH value
    let withdrawTokens;
    try {
      // Convert ETH value to token amount only if value is positive
      if (withdrawableValueInEth.gt(0)) {
        withdrawTokens = withdrawableValueInEth
          .mul(ethers.utils.parseUnits("1", primaryAsset.decimals))
          .div(primaryAsset.valuePerToken);
        
        console.log(`Theoretical maximum withdrawal amount: ${ethers.utils.formatUnits(withdrawTokens, primaryAsset.decimals)} ${primaryAsset.symbol}`);
      } else {
        // Use a TINY percentage of balance if no withdrawable amount
        const safeStartingPercentage = ethers.utils.parseUnits("0.001", 18); // 0.1% to be extremely cautious
        withdrawTokens = primaryAsset.balance.mul(safeStartingPercentage).div(ethers.utils.parseUnits("1", 18));
        console.log(`Using extremely small starting amount: ${ethers.utils.formatUnits(withdrawTokens, primaryAsset.decimals)} ${primaryAsset.symbol} (0.1% of balance)`);
      }
    } catch (err) {
      console.error("Error calculating theoretical withdrawal amount:", err.message);
      // Fallback: Use 0.1% of the balance as a starting point
      const safeStartingPercentage = ethers.utils.parseUnits("0.001", 18); // 0.1%
      withdrawTokens = primaryAsset.balance.mul(safeStartingPercentage).div(ethers.utils.parseUnits("1", 18));
      console.log(`Using fallback withdrawal amount: ${ethers.utils.formatUnits(withdrawTokens, primaryAsset.decimals)} ${primaryAsset.symbol} (0.1% of balance)`);
    }

    // For first attempt, use calculated amount without any rounding
    let withdrawalAmount = withdrawTokens;

    // No rounding, use exact values
    // Just ensure it's not more than the available balance
    if (withdrawalAmount.gt(primaryAsset.balance)) {
      console.log(`Calculated amount exceeds balance, capping at available balance`);
      withdrawalAmount = primaryAsset.balance;
    }

    console.log(`Starting with withdrawal of ${ethers.utils.formatUnits(withdrawalAmount, primaryAsset.decimals)} ${primaryAsset.symbol} (exact calculated amount)`);

    // Use custom amount if specified via command line
    if (CUSTOM_AMOUNT_VALUE) {
      try {
        withdrawalAmount = ethers.utils.parseUnits(CUSTOM_AMOUNT_VALUE, primaryAsset.decimals);
        
        // Ensure it's not more than the available balance
        if (withdrawalAmount.gt(primaryAsset.balance)) {
          console.log(`Specified amount exceeds balance, capping at available balance`);
          withdrawalAmount = primaryAsset.balance;
        }
        
        console.log(`Using command-line specified withdrawal amount: ${ethers.utils.formatUnits(withdrawalAmount, primaryAsset.decimals)} ${primaryAsset.symbol}`);
      } catch (err) {
        console.error(`Error parsing custom amount from command line: ${err.message}`);
        console.log(`Defaulting to calculated amount: ${ethers.utils.formatUnits(withdrawalAmount, primaryAsset.decimals)} ${primaryAsset.symbol}`);
      }
    } else {
      console.log("Using calculated withdrawal amount.");
    }

    // Log our strategy
    console.log("\n--- Optimal Withdrawal Strategy ---");
    console.log("After successful withdrawals: Recalculate optimal withdrawal amount based on new position state");
    console.log("After failed withdrawals: Try with 50% of the failed amount");
    console.log("This ensures maximum efficiency while handling LTV constraints\n");
    
    // Main loop
    let successfulTxs = 0;
    let attemptCount = 0;
    const MAX_ATTEMPTS = 40;
    
    // Track the last valid (positive) calculated amount and the very last attempted amount
    let lastValidCalculatedAmount = null;
    let lastAttemptedAmount = withdrawalAmount;

    while (successfulTxs < MAX_ITERATIONS && attemptCount < MAX_ATTEMPTS) {
      attemptCount++;
      
      console.log(`\n--- Attempt ${attemptCount} (Successful TXs: ${successfulTxs}/${MAX_ITERATIONS}) ---`);
      
      // Check wallet and position balances before transaction
      const erc20 = new ethers.Contract(primaryAsset.address, ERC20ABI, provider);
      const walletBalanceBefore = await erc20.balanceOf(wallet.address);
      const positionBalanceBefore = await erc20.balanceOf(POSITION_ADDRESS);
      
      console.log(`Wallet balance before: ${ethers.utils.formatUnits(walletBalanceBefore, primaryAsset.decimals)} ${primaryAsset.symbol}`);
      console.log(`Position balance before: ${ethers.utils.formatUnits(positionBalanceBefore, primaryAsset.decimals)} ${primaryAsset.symbol}`);
      
      // Save the current amount as last attempted
      lastAttemptedAmount = withdrawalAmount;
      
      // Perform withdrawal to wallet
      console.log(`Attempting withdrawal of ${ethers.utils.formatUnits(withdrawalAmount, primaryAsset.decimals)} ${primaryAsset.symbol}`);
      let success = await performWithdrawal(positionManager, primaryAsset.address, withdrawalAmount, wallet.address, primaryAsset.decimals, primaryAsset.symbol);
      
      // Check wallet and position balances after transaction
      const walletBalanceAfter = await erc20.balanceOf(wallet.address);
      const positionBalanceAfter = await erc20.balanceOf(POSITION_ADDRESS);
      
      console.log(`Wallet balance after: ${ethers.utils.formatUnits(walletBalanceAfter, primaryAsset.decimals)} ${primaryAsset.symbol}`);
      console.log(`Position balance after: ${ethers.utils.formatUnits(positionBalanceAfter, primaryAsset.decimals)} ${primaryAsset.symbol}`);
      
      // Calculate differences
      const walletDiff = walletBalanceAfter.sub(walletBalanceBefore);
      const positionDiff = positionBalanceBefore.sub(positionBalanceAfter);
      
      console.log(`Wallet balance change: ${ethers.utils.formatUnits(walletDiff, primaryAsset.decimals)} ${primaryAsset.symbol}`);
      console.log(`Position balance change: ${ethers.utils.formatUnits(positionDiff, primaryAsset.decimals)} ${primaryAsset.symbol}`);
      
      // Check if tokens were actually transferred
      if (walletDiff.isZero() || positionDiff.isZero()) {
        console.log("WARNING: No tokens were transferred despite transaction success!");
        if (success) {
          console.log("Transaction returned success but no tokens moved - investigating why:");
          
          // Debug information to understand why no tokens were transferred
          console.log(`1. Withdrawal amount: ${ethers.utils.formatUnits(withdrawalAmount, primaryAsset.decimals)} ${primaryAsset.symbol}`);
          console.log(`2. Transaction success status: ${success}`);
          
          // Check if position has sufficient balance
          if (positionBalanceBefore.lt(withdrawalAmount)) {
            console.log(`3. Position does not have sufficient balance (${ethers.utils.formatUnits(positionBalanceBefore, primaryAsset.decimals)} < ${ethers.utils.formatUnits(withdrawalAmount, primaryAsset.decimals)})}`);
          }
          
          // More detailed check of wallet and position differences
          console.log(`4. Wallet diff raw: ${walletDiff.toString()}`);
          console.log(`5. Position diff raw: ${positionDiff.toString()}`);
          
          // Correct the success flag
          console.log("Correcting success flag to false as no tokens were moved");
          success = false;
        }
      } else if (!walletDiff.eq(positionDiff)) {
        // If changes are not equal, still continue but warn
        console.log(`WARNING: Wallet change (${ethers.utils.formatUnits(walletDiff, primaryAsset.decimals)}) ` + 
                    `and position change (${ethers.utils.formatUnits(positionDiff, primaryAsset.decimals)}) are not equal.`);
        console.log("This may indicate fees being taken or other contract behavior.");
      }
      
      // Check health factor after transaction  
      const newHealthFactor = await riskEngine.getPositionHealthFactor(POSITION_ADDRESS);
      console.log(`Health factor after transaction: ${newHealthFactor.toString()} (${ethers.utils.formatUnits(newHealthFactor, 18)})`);
      
      // Get latest risk data to calculate current LTV
      const newRiskData = await riskEngine.getRiskData(POSITION_ADDRESS);
      const newTotalAssetValue = newRiskData.totalAssetValue;
      const newTotalDebtValue = newRiskData.totalDebtValue;
      
      // Calculate new LTV
      const newLTV = newTotalDebtValue.mul(ethers.utils.parseUnits('1', 18)).div(newTotalAssetValue);
      console.log(`LTV after transaction: ${ethers.utils.formatUnits(newLTV, 16)}% (max allowed: ${ethers.utils.formatUnits(MAX_LTV, 16)}%)`);
      console.log(`Distance to max LTV: ${ethers.utils.formatUnits(MAX_LTV.sub(newLTV), 16)}%`);
      
      // Compare with previous health factor to detect if transaction actually had an effect
      const healthFactorDifference = currentHealthFactor.sub(newHealthFactor).abs();
      const minExpectedChange = ethers.utils.parseUnits("0.000001", 18); // Very small change to detect if tx had any effect
      
      // If health factor didn't change and we claimed success, something is wrong
      if (success && healthFactorDifference.lt(minExpectedChange) && walletDiff.isZero()) {
        console.log("⚠️ WARNING: Transaction reported success but health factor didn't change!");
        console.log("This likely means the transaction was included but the withdrawal FAILED due to health check constraints.");
        console.log("Correcting success flag to FALSE.");
        success = false;
      }
      
      if (success) {
        successfulTxs++;
        console.log(`*** Successful transaction ${successfulTxs}/${MAX_ITERATIONS} completed ***`);
        
        // Store the last successful amount
        lastSuccessfulWithdrawal = withdrawalAmount;
        
        // Calculate the impact of our last withdrawal on the health factor
        const healthFactorReduction = currentHealthFactor.sub(newHealthFactor);
        const reductionPercentage = healthFactorReduction.mul(100).div(currentHealthFactor);
        console.log(`Last withdrawal reduced health factor by ${ethers.utils.formatUnits(reductionPercentage, 16)}%`);
        
        // Update current health factor
        currentHealthFactor = newHealthFactor;
        
        // AFTER SUCCESS: Recalculate optimum withdrawal amount
        console.log("Success! Recalculating optimal withdrawal amount based on new position state...");
        
        // Recalculate optimal withdrawal amount from the updated position
        let recalculatedWithdrawValueInEth = newTotalAssetValue.sub(
          newTotalDebtValue.mul(ethers.utils.parseUnits('1', 18)).div(MAX_LTV)
        );
        
        // Apply safety factor
        const WEI = ethers.BigNumber.from(10).pow(18);
        const SAFETY_FACTOR = ethers.BigNumber.from(999).mul(WEI).div(1000); // 99.9% to be very safe
        recalculatedWithdrawValueInEth = recalculatedWithdrawValueInEth.mul(SAFETY_FACTOR).div(WEI);
        
        console.log(`Recalculated withdrawable value: ${ethers.utils.formatEther(recalculatedWithdrawValueInEth)} ETH`);
        
        // If calculated amount is negative or zero, use fallbacks
        if (recalculatedWithdrawValueInEth.lte(0)) {
          console.log("Calculated withdrawable amount is zero or negative.");
          
          // Use a small percentage of the remaining balance
          withdrawalAmount = positionBalanceAfter.mul(MIN_FALLBACK_PERCENTAGE).div(ethers.utils.parseUnits("1", 18));
          console.log(`Using minimum fallback amount: ${ethers.utils.formatUnits(withdrawalAmount, primaryAsset.decimals)} ${primaryAsset.symbol} (${ethers.utils.formatUnits(MIN_FALLBACK_PERCENTAGE, 16)}% of remaining balance)`);
        } else {
          // Convert ETH value to token amount
          withdrawalAmount = recalculatedWithdrawValueInEth
            .mul(ethers.utils.parseUnits("1", primaryAsset.decimals))
            .div(primaryAsset.valuePerToken);
          
          console.log(`Next optimal withdrawal amount: ${ethers.utils.formatUnits(withdrawalAmount, primaryAsset.decimals)} ${primaryAsset.symbol}`);
          
          // Store this as the last valid calculated amount
          lastValidCalculatedAmount = withdrawalAmount;
        }
        
        // Don't exceed position balance
        if (withdrawalAmount.gt(positionBalanceAfter)) {
          withdrawalAmount = positionBalanceAfter;
          console.log(`Capped at position balance: ${ethers.utils.formatUnits(withdrawalAmount, primaryAsset.decimals)} ${primaryAsset.symbol}`);
        }
        
        // Check if we're below target or close enough
        if (newHealthFactor.lte(TARGET_HEALTH_FACTOR)) {
          console.log(`Target health factor reached. Stopping.`);
          break;
        }
      } else {
        console.log("Transaction failed. Adjusting withdrawal amount downward.");
        
        // Check if the failure was due to health check
        if (success === false && 
            (typeof success === 'object' && success.reason && 
             (success.reason.includes("HealthCheckFailed") || 
              success.reason.includes("health factor")))) {
          console.log("⚠️ TRANSACTION FAILED DUE TO HEALTH CHECK ⚠️");
          console.log("This means your withdrawal amount was too high and would have made the position unsafe.");
        } else {
          console.log("Transaction failed. This could be due to health check or other constraints.");
        }
        
        // AFTER FAILURE: Try 50% of last attempted amount
        withdrawalAmount = lastAttemptedAmount.mul(50).div(100);
        console.log(`Next attempt: ${ethers.utils.formatUnits(withdrawalAmount, primaryAsset.decimals)} ${primaryAsset.symbol} (50% of last attempted amount)`);
        
        // If we go too small, make sure we're not wasting time with tiny amounts
        if (withdrawalAmount.lt(ethers.utils.parseUnits("0.000001", primaryAsset.decimals))) {
          console.log("Withdrawal amount has become too small. Increasing to a minimum meaningful amount.");
          withdrawalAmount = ethers.utils.parseUnits("0.000001", primaryAsset.decimals);
        }
      }
      
      // Log current health factor
      console.log(`Current health factor: ${currentHealthFactor.toString()} (${ethers.utils.formatUnits(currentHealthFactor, 18)})`);
      
      // Check if we're below target or close enough
      if (currentHealthFactor.lte(TARGET_HEALTH_FACTOR)) {
        console.log(`Health factor is at or below target. Stopping.`);
        break;
      }
      
      const difference = currentHealthFactor.sub(TARGET_HEALTH_FACTOR);
      console.log(`Difference from target: ${ethers.utils.formatUnits(difference, 18)}`);
      
      if (difference.lte(THRESHOLD_PRECISION)) {
        console.log(`Health factor is close enough to target (within ${ethers.utils.formatUnits(THRESHOLD_PRECISION, 18)}). Stopping.`);
        break;
      }
    }
    
    console.log("\n--- Final Results ---");
    
    if (successfulTxs >= MAX_ITERATIONS) {
      console.log(`Reached maximum iterations (${MAX_ITERATIONS} successful TXs). Final health factor: ${ethers.utils.formatUnits(currentHealthFactor, 18)}`);
    } else if (attemptCount >= MAX_ATTEMPTS) {
      console.log(`Reached maximum attempts (${MAX_ATTEMPTS}). Final health factor: ${ethers.utils.formatUnits(currentHealthFactor, 18)}`);
    } else if (currentHealthFactor.lte(TARGET_HEALTH_FACTOR)) {
      console.log(`Successfully brought health factor below target: ${ethers.utils.formatUnits(currentHealthFactor, 18)}`);
    } else {
      console.log(`Successfully brought health factor close to target: ${ethers.utils.formatUnits(currentHealthFactor, 18)}`);
    }
    
  } catch (error) {
    console.error("Error in main process:", error);
  }
}

async function getAssetDetails(assets, position, riskEngine, provider) {
  const assetDetails = [];
  
  for (const asset of assets) {
    const erc20 = new ethers.Contract(asset, ERC20ABI, provider);
    const assetBalance = await erc20.balanceOf(POSITION_ADDRESS);
    
    if (assetBalance.isZero()) continue;
    
    // Get symbol and decimals
    let symbol = "";
    try {
      symbol = await erc20.symbol();
    } catch (error) {
      symbol = asset.slice(0, 8) + "...";
    }
    
    const decimals = await erc20.decimals();
    
    // Get value in ETH
    const valueInEth = await riskEngine.getValueInEth(asset, assetBalance);
    
    assetDetails.push({
      address: asset,
      balance: assetBalance,
      symbol,
      decimals,
      valueInEth,
      valuePerToken: valueInEth.mul(ethers.utils.parseUnits("1", decimals)).div(assetBalance)
    });
  }
  
  return assetDetails;
}

async function performWithdrawal(positionManager, assetAddress, withdrawAmount, recipient, decimals = 18, symbol = "tokens") {
  // Skip extremely tiny amounts that might cause precision issues
  if (withdrawAmount.isZero()) {
    console.log("Withdrawal amount is zero. Skipping transaction.");
    return false;
  }

  // Minimum amount to avoid dust and rounding errors
  const MIN_AMOUNT = ethers.BigNumber.from(10); // Smallest sensible amount
  if (withdrawAmount.lt(MIN_AMOUNT)) {
    console.log(`Withdrawal amount (${withdrawAmount.toString()}) is too small and may not have any effect. Increasing to minimum.`);
    withdrawAmount = MIN_AMOUNT;
  }

  // Create the action data
  const action = createTransferAction(recipient, assetAddress, withdrawAmount);
  console.log("Sending transaction...");
  
  // Log action data details for debugging
  console.log(`Action operation: ${action.op} (Transfer, expected code 3)`);
  console.log(`Action data length: ${action.data.length} bytes`);
  console.log(`Withdrawal amount in transaction: ${withdrawAmount.toString()} (${ethers.utils.formatUnits(withdrawAmount, decimals)} ${symbol})`);
  
  // Get the encoded calldata for the process function call
  const calldata = positionManager.interface.encodeFunctionData(
    'process',
    [POSITION_ADDRESS, action]
  );
  console.log(`Full calldata: ${calldata}`);
  
  try {
    // Get gas price for better debugging
    const gasPrice = await positionManager.provider.getGasPrice();
    console.log(`Current gas price: ${ethers.utils.formatUnits(gasPrice, 'gwei')} gwei`);
    
    // Execute the transaction
    const tx = await positionManager.process(POSITION_ADDRESS, action, {
      gasLimit: 1000000, // Set explicit gas limit to avoid estimation issues
      gasPrice: gasPrice.mul(110).div(100) // Add 10% to gas price for faster confirmation
    });
    console.log(`Transaction sent: ${tx.hash}`);
    
    // Wait for confirmation
    console.log(`Waiting for confirmation...`);
    const receipt = await tx.wait();
    console.log(`Transaction confirmed with status: ${receipt.status}`);
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    console.log(`Block number: ${receipt.blockNumber}`);
    
    // Use the helper function to analyze the transaction receipt
    const analysis = analyzeTransactionReceipt(receipt, tx);
    
    if (!analysis.success) {
      console.log(`❌ Transaction analysis detected failure: ${analysis.reason}`);
      return false;
    }
    
    console.log(`✅ Transaction analysis confirmed success: ${analysis.reason}`);
    
    // The rest of the checks below are kept as additional verification
    // Check for relevant events
    console.log(`Additional verification of transaction logs...`);
    
    // Check for any revert events/errors in the logs including "HealthCheckFailed"
    const revertEvents = receipt.logs
      .filter(log => log.topics.length > 0)
      .filter(log => {
        try {
          // Look for any error events
          return log.topics[0].includes("Error") || log.topics[0].includes("Failed") || 
                 (log.topics[0].length > 10 && log.data && log.data.includes("HealthCheckFailed"));
        } catch (e) {
          return false;
        }
      });
    
    if (revertEvents.length > 0) {
      console.log("WARNING: Error events found in transaction logs!");
      console.log("This indicates the transaction was included in a block but REVERTED during execution.");
      
      for (const evt of revertEvents) {
        console.log(`Error event found: ${JSON.stringify(evt)}`);
      }
      
      console.log("⚠️ TRANSACTION FAILED: Health check or other constraint failed even though transaction was included ⚠️");
      return false;
    }
    
    // Specifically check the transaction data for any health factor errors
    if (receipt.logs && receipt.logs.length > 0) {
      for (const log of receipt.logs) {
        if (log.data && (log.data.includes("HealthCheckFailed") || log.data.includes("health"))) {
          console.log("⚠️ HEALTH CHECK FAILED event found in transaction logs! ⚠️");
          console.log(`Log data: ${log.data}`);
          return false;
        }
      }
    }
    
    const transferEvents = receipt.logs
      .filter(log => log.topics.length > 0)
      .filter(log => {
        try {
          // Look for Transfer events from the position manager
          return log.topics[0] === ethers.utils.id("Transfer(address,address,address,address,uint256)");
        } catch (e) {
          return false;
        }
      });
    
    if (transferEvents.length === 0) {
      console.log("WARNING: No Transfer events found in the transaction logs!");
      
      // Check for token transfer events (standard ERC20 Transfer)
      const erc20TransferEvents = receipt.logs
        .filter(log => log.topics.length > 0)
        .filter(log => {
          try {
            return log.topics[0] === ethers.utils.id("Transfer(address,address,uint256)");
          } catch (e) {
            return false;
          }
        });
      
      if (erc20TransferEvents.length === 0) {
        console.log("WARNING: No ERC20 Transfer events found either!");
        console.log("⚠️ TRANSACTION FAILED: Transaction was included but no tokens were transferred ⚠️");
        
        // Try to determine why the transaction succeeded but no tokens were transferred
        console.log("This indicates the transaction was accepted but the transfer failed.");
        console.log("Possible reasons: health factor violation, insufficient permissions, asset not in position, or other contract constraint.");
        return false;
      } else {
        console.log(`Found ${erc20TransferEvents.length} ERC20 Transfer events in logs`);
        // Check if any of these transfers match our expected amount and recipient
        let foundMatchingTransfer = false;
        for (const event of erc20TransferEvents) {
          if (event.topics.length >= 3) {
            try {
              // Parse the event data
              const fromAddress = '0x' + event.topics[1].slice(26);
              const toAddress = '0x' + event.topics[2].slice(26);
              let transferAmount;
              
              if (event.data && event.data !== '0x') {
                transferAmount = ethers.BigNumber.from(event.data);
              }
              
              console.log(`ERC20 Transfer: ${fromAddress} -> ${toAddress}, Amount: ${transferAmount ? transferAmount.toString() : 'unknown'}`);
              
              if (toAddress.toLowerCase() === recipient.toLowerCase() && 
                  transferAmount && transferAmount.eq(withdrawAmount)) {
                console.log("Found matching ERC20 transfer event!");
                foundMatchingTransfer = true;
              }
            } catch (e) {
              console.log(`Error parsing ERC20 transfer event: ${e.message}`);
            }
          }
        }
        
        return foundMatchingTransfer;
      }
    } else {
      console.log(`Found ${transferEvents.length} Transfer events in logs`);
      return true;
    }
  } catch (error) {
    console.error("Transaction failed:", error.message);
    
    // Look specifically for health factor failures in the error message
    if (error.message && (
        error.message.includes("HealthCheckFailed") || 
        error.message.includes("health factor") || 
        error.message.includes("PositionManager_HealthCheckFailed"))) {
      console.log("⚠️ HEALTH CHECK FAILED: Transaction reverted due to health factor violation ⚠️");
    }
    
    // Provide more detailed error information
    if (error.data) {
      console.error("Error data:", error.data);
    }
    
    if (error.reason) {
      console.error("Error reason:", error.reason);
    }
    
    // Try to extract more information from the error
    if (error.code === 'UNPREDICTABLE_GAS_LIMIT') {
      console.error("Transaction failed with unpredictable gas limit. This usually indicates a revert in the contract.");
    }
    
    // If available, try to call the function with callStatic to get revert reason
    try {
      console.log("Attempting static call to understand the error...");
      await positionManager.callStatic.process(POSITION_ADDRESS, action);
    } catch (staticError) {
      console.error("Static call error:", staticError.message);
      if (staticError.errorArgs) {
        console.error("Error arguments:", staticError.errorArgs);
      }
      
      // Check for health check failures in static call
      if (staticError.message && (
          staticError.message.includes("HealthCheckFailed") || 
          staticError.message.includes("health factor") ||
          staticError.message.includes("PositionManager_HealthCheckFailed"))) {
        console.log("⚠️ HEALTH CHECK FAILED: Static call confirms health factor violation ⚠️");
      }
    }
    
    return false;
  }
}

function createTransferAction(recipient, asset, amount) {
  // IMPORTANT: Fixed order according to contract in PositionManager.sol
  // Function: transfer(address position, bytes calldata data)
  // - data -> abi.encodePacked(address, address, uint256)
  // - recipient -> [0:20] address that will receive the transferred tokens
  // - asset -> [20:40] address of token to be transferred
  // - amt -> [40:72] amount of asset to be transferred
  
  // Log the parameters
  console.log(`Transfer parameters:`);
  console.log(`  Recipient: ${recipient}`);
  console.log(`  Asset: ${asset}`);
  console.log(`  Amount: ${amount.toString()}`);
  
  // Ensure we're not sending 0 tokens
  if (amount.isZero()) {
    console.log(`  WARNING: Transfer amount is zero. This may not be effective.`);
  }
  
  // Make sure withdrawal amount is valid
  if (amount.lt(0)) {
    console.log(`  ERROR: Negative withdrawal amount: ${amount.toString()}`);
    throw new Error(`Cannot withdraw negative amount: ${amount.toString()}`);
  }
  
  try {
    // Pack the data in the correct order: recipient, asset, amount
    // Using BigNumber object directly for packing can cause issues
    // Make sure we convert to hex string with no leading zeros (except for 0 value)
    const amountHex = amount.isZero() ? '0x0' : amount.toHexString();
    
    console.log(`  Amount hex: ${amountHex}`);
    
    const data = ethers.utils.solidityPack(
      ['address', 'address', 'uint256'],
      [recipient, asset, amountHex]
    );
    
    // Log the hex representation for debugging
    console.log(`  Packed data: ${data}`);
    console.log(`  Data length: ${data.length} bytes`);
    
    // Return the action object with operation type = Transfer (3)
    return {
      op: Operation.Transfer,
      data: data
    };
  } catch (error) {
    console.error("Error creating transfer action:", error);
    console.error("Error message:", error.message);
    console.error("Error stack:", error.stack);
    throw error;
  }
}

// Helper function to analyze transaction receipt for health check and other errors
function analyzeTransactionReceipt(receipt, tx) {
  console.log("🔍 Analyzing transaction receipt for errors and events...");
  
  // First check if there's any data in the transaction that might indicate errors
  if (receipt.logs && receipt.logs.length > 0) {
    // Check for known error strings in the logs
    const knownErrorPatterns = [
      "HealthCheckFailed",
      "health factor",
      "PositionManager_HealthCheckFailed",
      "health constraint",
      "Error",
      "Reverted",
      "Failed"
    ];
    
    for (const log of receipt.logs) {
      if (log.data) {
        const logData = log.data.toLowerCase();
        
        for (const errorPattern of knownErrorPatterns) {
          if (logData.includes(errorPattern.toLowerCase())) {
            console.log(`❌ Error detected in transaction log: ${errorPattern}`);
            console.log(`Log data: ${log.data}`);
            return {
              success: false,
              reason: `Transaction reverted with error: ${errorPattern}`
            };
          }
        }
      }
      
      // Check topics for known error signatures
      if (log.topics && log.topics.length > 0) {
        // Known error event signatures
        const errorEventSignatures = [
          ethers.utils.id("Error(string)"),
          ethers.utils.id("Failure(string)"),
          ethers.utils.id("HealthCheckFailed(address,uint256)")
        ];
        
        for (const sig of errorEventSignatures) {
          if (log.topics[0] === sig) {
            console.log(`❌ Error event detected: ${sig}`);
            return {
              success: false,
              reason: `Transaction emitted error event: ${sig}`
            };
          }
        }
      }
    }
  }
  
  // If we made it here, no obvious errors were found in the logs
  // Check for Transfer events to confirm if tokens actually moved
  const transferEvents = receipt.logs
    .filter(log => log.topics.length > 0)
    .filter(log => {
      try {
        return log.topics[0] === ethers.utils.id("Transfer(address,address,uint256)");
      } catch (e) {
        return false;
      }
    });
  
  if (transferEvents.length === 0) {
    console.log("❓ No Transfer events found in transaction logs");
    console.log("This usually indicates the transaction was accepted but no tokens were transferred");
    return {
      success: false,
      reason: "No tokens were transferred despite transaction success"
    };
  }
  
  // If we got here, the transaction appears successful
  console.log(`✅ Found ${transferEvents.length} Transfer events in transaction logs`);
  return {
    success: true,
    reason: `Transaction completed with ${transferEvents.length} token transfers`
  };
}

// Run the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 