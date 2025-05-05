import { ethers } from 'ethers';
import * as fs from 'fs';

// Oracle pair structure
interface OraclePair {
  current: string;
  new: string;
}

// Default Oracle addresses
const DEFAULT_ORACLE_PAIRS: Record<string, OraclePair> = {
  wHype: {
    current: '0x712047cC3e4b0023Fccc09Ae412648CF23C65ed3',
    new: '0x8B8899d0A20ae32e052F9410c23B04E934192d6b'
  },
  wstHype: {
    current: '0x619b82845177a163681b08e7684a2bb968011c68',
    new: '0x19386c918eE714bFF7c79B89e33F1D70F4930284'
  }
};

// Default Token addresses - always used
const DEFAULT_TOKENS: Record<string, string> = {
  wHype: '0x5555555555555555555555555555555555555555',
  wstHype: '0x94e8396e0869c9F2200760aF0621aFd240E1CF38'
};

// ETH/USD price feed (from RiskView.s.sol)
const ETH_USD_FEED = '0x1b27A24642B1a5a3c54452DDc02F278fb6F63229';

// Oracle ABI - minimal interface just for the functions we need
const oracleAbi = [
  'function getValueInEth(address asset, uint256 amt) external view returns (uint256 valueInEth)'
];

// ERC20 token ABI for getting token symbols
const erc20Abi = [
  'function symbol() external view returns (string)',
  'function name() external view returns (string)'
];

// Chainlink Aggregator ABI for ETH/USD feed
const aggregatorAbi = [
  'function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)'
];

// Application configuration
interface Config {
  mainRpcUrl: string;
  checkInterval: number;
  numChecks: number;
  logFile: string;
}

// Configuration
const CONFIG: Config = {
  mainRpcUrl: 'https://rpc.hyperliquid.xyz/evm',
  checkInterval: 60000, // 1 minute between checks
  numChecks: 0, // 0 for infinite checks
  logFile: 'script/logs/risk/oracle-price-log.json'
};

// Oracle contract interface
interface OracleContract extends ethers.Contract {
  getValueInEth(asset: string, amount: ethers.BigNumber): Promise<ethers.BigNumber>;
}

// ERC20 token interface
interface ERC20Contract extends ethers.Contract {
  symbol(): Promise<string>;
  name(): Promise<string>;
}

// Chainlink Aggregator interface
interface AggregatorContract extends ethers.Contract {
  latestRoundData(): Promise<[ethers.BigNumber, ethers.BigNumber, ethers.BigNumber, ethers.BigNumber, ethers.BigNumber]>;
}

// Oracle pair for comparison
interface OraclePairForComparison {
  name: string;
  currentOracle: OracleContract;
  newOracle: OracleContract;
  assetAddress: string;
  assetSymbol: string;
}

// Price log entry structure
interface PriceLogEntry {
  timestamp: number;
  blockNumber: number;
  ethUsdPrice: string;
  [key: string]: any;
}

// Price data structure
interface PriceData {
  current: {
    eth: string;
    usd: string;
  };
  new: {
    eth: string;
    usd: string;
  };
  diffPercentage: number;
}

// Initialize provider
let mainProvider: ethers.providers.JsonRpcProvider;
let ethUsdFeed: AggregatorContract;

// Oracle pairs for comparison
let oraclePairs: OraclePairForComparison[] = [];

// Data storage
let priceLog: PriceLogEntry[] = [];

// Load existing log if available
function loadExistingLog(): void {
  try {
    if (fs.existsSync(CONFIG.logFile)) {
      const data = fs.readFileSync(CONFIG.logFile, 'utf8');
      priceLog = JSON.parse(data);
      console.log(`Loaded ${priceLog.length} existing price records`);
    }
  } catch (error) {
    console.error('Error loading existing log:', error);
  }
}

// Save log to file
function saveLog(): void {
  try {
    fs.writeFileSync(CONFIG.logFile, JSON.stringify(priceLog, null, 2));
    console.log(`Saved log to ${CONFIG.logFile}`);
  } catch (error) {
    console.error('Error saving log:', error);
  }
}

// Helper to get token symbol from address
async function getTokenSymbol(address: string): Promise<string> {
  try {
    const token = new ethers.Contract(address, erc20Abi, mainProvider) as ERC20Contract;
    return await token.symbol();
  } catch (error) {
    try {
      const token = new ethers.Contract(address, erc20Abi, mainProvider) as ERC20Contract;
      return await token.name();
    } catch (error) {
      // If we can't get the symbol or name, return the address
      return address;
    }
  }
}

// Initialize ethers contracts
async function initializeContracts(customOracles: string[] | null = null): Promise<void> {
  mainProvider = new ethers.providers.JsonRpcProvider(CONFIG.mainRpcUrl);

  // Initialize ETH/USD price feed
  ethUsdFeed = new ethers.Contract(ETH_USD_FEED, aggregatorAbi, mainProvider) as AggregatorContract;
  
  // Clear existing oracle pairs
  oraclePairs = [];
  
  // If custom oracles are provided, use them
  if (customOracles && customOracles.length > 0) {
    for (let i = 0; i < customOracles.length; i += 2) {
      if (i + 1 < customOracles.length) {
        const currentOracle = new ethers.Contract(customOracles[i], oracleAbi, mainProvider) as OracleContract;
        const newOracle = new ethers.Contract(customOracles[i + 1], oracleAbi, mainProvider) as OracleContract;
        
        // Use a default asset address for custom oracles
        const assetAddress = `0x${'1'.padStart(40, '0')}${i.toString().padStart(2, '0')}`;
        
        // Get token symbol
        const assetSymbol = await getTokenSymbol(assetAddress);
        
        oraclePairs.push({
          name: `Oracle${i/2 + 1}`,
          currentOracle,
          newOracle,
          assetAddress,
          assetSymbol
        });
      }
    }
  } else {
    // Use default oracle pairs
    // wHype
    const whypeOracleCurrent = new ethers.Contract(DEFAULT_ORACLE_PAIRS.wHype.current, oracleAbi, mainProvider) as OracleContract;
    const whypeOracleNew = new ethers.Contract(DEFAULT_ORACLE_PAIRS.wHype.new, oracleAbi, mainProvider) as OracleContract;
    const whypeAsset = DEFAULT_TOKENS.wHype;
    const whypeSymbol = await getTokenSymbol(whypeAsset);
    
    oraclePairs.push({
      name: 'wHype',
      currentOracle: whypeOracleCurrent,
      newOracle: whypeOracleNew,
      assetAddress: whypeAsset,
      assetSymbol: whypeSymbol
    });
    
    // wstHype
    const wstHypeOracleCurrent = new ethers.Contract(DEFAULT_ORACLE_PAIRS.wstHype.current, oracleAbi, mainProvider) as OracleContract;
    const wstHypeOracleNew = new ethers.Contract(DEFAULT_ORACLE_PAIRS.wstHype.new, oracleAbi, mainProvider) as OracleContract;
    const wstHypeAsset = DEFAULT_TOKENS.wstHype;
    const wstHypeSymbol = await getTokenSymbol(wstHypeAsset);
    
    oraclePairs.push({
      name: 'wstHype',
      currentOracle: wstHypeOracleCurrent,
      newOracle: wstHypeOracleNew,
      assetAddress: wstHypeAsset,
      assetSymbol: wstHypeSymbol
    });
  }
}

// Get ETH/USD price from Chainlink feed
async function getEthUsdPrice(): Promise<ethers.BigNumber> {
  try {
    // Fetch the latest ETH/USD price from Chainlink
    const [, answer] = await ethUsdFeed.latestRoundData();
    return answer;
  } catch (error) {
    console.error('Error fetching ETH/USD price:', error);
    return ethers.BigNumber.from(0);
  }
}

// Convert ETH value to USD
async function ethToUsd(ethValue: ethers.BigNumber): Promise<ethers.BigNumber> {
  const ethUsdPrice = await getEthUsdPrice();
  return ethValue.mul(ethUsdPrice).div(ethers.BigNumber.from(10).pow(8));
}

// Calculate percentage difference
function calculatePercentageDiff(current: ethers.BigNumber, new_: ethers.BigNumber): number {
  const diff = new_.sub(current);
  return diff.mul(ethers.BigNumber.from(10000)).div(current).toNumber() / 100;
}

// Check current prices and log differences
async function checkCurrentPrices(): Promise<boolean> {
  try {
    const blockNumber = await mainProvider.getBlockNumber();
    const timestamp = Math.floor(Date.now() / 1000);
    
    console.log(`\n=== Oracle Check at Block ${blockNumber} (${new Date().toISOString()}) ===`);
    
    // Get ETH/USD price
    const ethUsdPrice = await getEthUsdPrice();
    console.log(`ETH/USD Price: $${ethers.utils.formatUnits(ethUsdPrice, 8)}`);
    
    // Log entry object to store all results
    const entry: PriceLogEntry = {
      timestamp,
      blockNumber,
      ethUsdPrice: ethUsdPrice.toString()
    };
    
    // Format prices for display
    const formatPriceEth = (bn: ethers.BigNumber): string => {
      const eth = ethers.utils.formatEther(bn);
      return `${eth} ETH`;
    };
    
    const formatPriceUsd = (bn: ethers.BigNumber): string => {
      const usd = ethers.utils.formatUnits(bn, 18);
      return `$${parseFloat(usd).toFixed(2)}`;
    };
    
    // Check each oracle pair
    for (const pair of oraclePairs) {
      console.log(`\n${pair.name}:`);
      console.log(`  Asset: ${pair.assetSymbol}`);
      
      // Get prices in ETH
      const currentPrice = await pair.currentOracle.getValueInEth(
        pair.assetAddress, 
        ethers.utils.parseEther('1')
      );
      
      const newPrice = await pair.newOracle.getValueInEth(
        pair.assetAddress, 
        ethers.utils.parseEther('1')
      );
      
      // Get prices in USD
      const currentPriceUsd = currentPrice.mul(ethUsdPrice).div(ethers.BigNumber.from(10).pow(8));
      const newPriceUsd = newPrice.mul(ethUsdPrice).div(ethers.BigNumber.from(10).pow(8));
      
      // Calculate difference
      const diffPercentage = calculatePercentageDiff(currentPrice, newPrice);
      
      // Add to log entry
      entry[pair.name] = {
        current: {
          eth: currentPrice.toString(),
          usd: currentPriceUsd.toString()
        },
        new: {
          eth: newPrice.toString(),
          usd: newPriceUsd.toString()
        },
        diffPercentage
      };
      
      // Print results
      console.log(`  Current Oracle: ${formatPriceEth(currentPrice)} (${formatPriceUsd(currentPriceUsd)})`);
      console.log(`  New Oracle: ${formatPriceEth(newPrice)} (${formatPriceUsd(newPriceUsd)})`);
      console.log(`  Difference: ${diffPercentage > 0 ? '+' : ''}${diffPercentage.toFixed(4)}%`);
    }
    
    // Add to log and save
    priceLog.push(entry);
    saveLog();
    
    return true;
  } catch (error) {
    console.error('Error checking prices:', error);
    return false;
  }
}

// Main monitoring function
async function monitorPrices(): Promise<void> {
  let checkCount = 0;
  
  // Run first check immediately
  await checkCurrentPrices();
  checkCount++;
  
  // Continue checking if numChecks is 0 (infinite) or we haven't reached the limit
  if (CONFIG.numChecks === 0 || checkCount < CONFIG.numChecks) {
    console.log(`Next check in ${CONFIG.checkInterval / 1000} seconds...`);
    setTimeout(async () => {
      await monitorPrices();
    }, CONFIG.checkInterval);
  }
}

// Generate summary report
function generateSummaryReport(): void {
  if (priceLog.length === 0) {
    console.log('No data available for summary report');
    return;
  }
  
  console.log('\n=== Summary Report ===');
  
  // Get all asset names from the log entries
  const assetNames = new Set<string>();
  priceLog.forEach(entry => {
    Object.keys(entry).forEach(key => {
      if (key !== 'timestamp' && key !== 'blockNumber' && key !== 'ethUsdPrice') {
        assetNames.add(key);
      }
    });
  });
  
  // Process each asset
  for (const assetName of assetNames) {
    // Get all entries with data for this asset
    const entries = priceLog.filter(entry => entry[assetName]);
    
    if (entries.length === 0) continue;
    
    // Calculate percentage differences
    const diffs = entries.map(entry => entry[assetName].diffPercentage as number);
    const min = Math.min(...diffs);
    const max = Math.max(...diffs);
    const avg = diffs.reduce((sum, val) => sum + val, 0) / diffs.length;
    
    console.log(`\n${assetName} Difference (%)`);
    console.log(`  Minimum: ${min.toFixed(4)}%`);
    console.log(`  Maximum: ${max.toFixed(4)}%`);
    console.log(`  Average: ${avg.toFixed(4)}%`);
    console.log(`  Range: [${min.toFixed(4)}%, ${max.toFixed(4)}%]`);
    
    // Count positive vs negative differences
    const positive = diffs.filter(d => d > 0).length;
    const negative = diffs.filter(d => d < 0).length;
    const equal = diffs.filter(d => d === 0).length;
    
    console.log('\nNew Oracle Price Comparison:');
    console.log(`  Higher than current: ${positive} times (${(positive / diffs.length * 100).toFixed(2)}%)`);
    console.log(`  Lower than current: ${negative} times (${(negative / diffs.length * 100).toFixed(2)}%)`);
    console.log(`  Equal to current: ${equal} times (${(equal / diffs.length * 100).toFixed(2)}%)`);
    
    // Show average USD prices if available
    if (entries.some(entry => entry[assetName]?.current?.usd)) {
      console.log('\nAverage Prices (USD):');
      
      const currentUsdPrices = entries
        .filter(entry => entry[assetName]?.current?.usd)
        .map(entry => BigInt(entry[assetName].current.usd));
      
      const newUsdPrices = entries
        .filter(entry => entry[assetName]?.new?.usd)
        .map(entry => BigInt(entry[assetName].new.usd));
      
      if (currentUsdPrices.length > 0 && newUsdPrices.length > 0) {
        const currentUsdAvg = Number(currentUsdPrices.reduce((a, b) => a + b, BigInt(0)) / BigInt(currentUsdPrices.length)) / 1e18;
        const newUsdAvg = Number(newUsdPrices.reduce((a, b) => a + b, BigInt(0)) / BigInt(newUsdPrices.length)) / 1e18;
        
        console.log(`  Current Oracle: $${currentUsdAvg.toFixed(2)}`);
        console.log(`  New Oracle: $${newUsdAvg.toFixed(2)}`);
      }
    } else {
      console.log('\nNote: USD price data not available for this asset.');
    }
  }
}

// Command line arguments interface
interface CommandArgs {
  command: string;
  oracleAddresses: string[];
}

// Parse command line arguments
function parseArgs(): CommandArgs {
  const args = process.argv.slice(2);
  const command = args[0] || 'monitor';
  
  // Extract oracle addresses if provided (after the command)
  const oracleAddresses: string[] = [];
  for (let i = 1; i < args.length; i++) {
    // If argument starts with 0x, it's likely an address
    if (args[i].startsWith('0x')) {
      oracleAddresses.push(args[i]);
    } else if (['--interval', '-i'].includes(args[i]) && i + 1 < args.length) {
      // Handle interval parameter
      CONFIG.checkInterval = parseInt(args[i + 1], 10) * 1000; // Convert from seconds to ms
      i++; // Skip the next arg which is the value
    } else if (['--count', '-c'].includes(args[i]) && i + 1 < args.length) {
      // Handle count parameter
      CONFIG.numChecks = parseInt(args[i + 1], 10);
      i++; // Skip the next arg which is the value
    } else if (['--log', '-l'].includes(args[i]) && i + 1 < args.length) {
      // Handle log file parameter
      CONFIG.logFile = args[i + 1];
      i++; // Skip the next arg which is the value
    }
  }
  
  return { command, oracleAddresses };
}

// Display help
function showHelp(): void {
  console.log(`
Oracle Price Comparison Tool

Usage:
  npx ts-node script/risk/oracle-compare.ts [command] [options] [addresses]

Commands:
  monitor               Start continuous monitoring
  check                 Perform a single check
  report                Generate summary report from saved data
  help                  Show this help message

Options:
  -i, --interval <sec>  Check interval in seconds (for monitor)
  -c, --count <num>     Number of checks to perform (0 for infinite)
  -l, --log <file>      Log file path

Examples:
  # Use default oracle pairs
  npx ts-node script/risk/oracle-compare.ts check
  
  # Compare custom oracle pairs (must provide pairs of addresses)
  npx ts-node script/risk/oracle-compare.ts check 0x123...abc 0x456...def 0x789...fed 0xabc...123
  
  # Monitor with 5-minute interval
  npx ts-node script/risk/oracle-compare.ts monitor --interval 300
  `);
}

// Main function
async function main(): Promise<void> {
  const { command, oracleAddresses } = parseArgs();
  
  if (command === 'help') {
    showHelp();
    return;
  }
  
  // Initialize
  try {
    await initializeContracts(oracleAddresses.length > 0 ? oracleAddresses : null);
    
    loadExistingLog();
    
    switch (command) {
      case 'monitor':
        console.log('Starting oracle price monitoring...');
        await monitorPrices();
        break;
      
      case 'report':
        generateSummaryReport();
        break;
        
      case 'check':
        await checkCurrentPrices();
        break;
        
      default:
        showHelp();
    }
  } catch (error) {
    console.error('Error in main execution:', error);
  }
}

// Execute main
main().catch(console.error); 
