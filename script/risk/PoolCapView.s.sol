// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseScript} from "../BaseScript.s.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IOracle} from "src/interfaces/IOracle.sol";

// Interfaces
interface IPool {
    function riskEngine() external view returns (address);
    function getRateModelFor(uint256 poolId) external view returns (address);
    function getPoolAssetFor(uint256 poolId) external view returns (address);
    function getTotalBorrows(uint256 poolId) external view returns (uint256);
    function getTotalAssets(uint256 poolId) external view returns (uint256);
    function getAssetsOf(
        uint256 poolId,
        address account
    ) external view returns (uint256);
    function getBorrowsOf(
        uint256 poolId,
        address account
    ) external view returns (uint256);
    function getBorrowCapFor(uint256 poolId) external view returns (uint256);
    function getPoolCapFor(uint256 poolId) external view returns (uint256);
}

interface IRiskEngine {
    function oracleFor(address asset) external view returns (address);
}

interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/// @dev to run script:
/// forge script PoolCapView --sig "viewAllPools()" --rpc-url \
/// https://rpc.hyperliquid.xyz/evm
///
/// forge script PoolCapView --sig "viewPool(string)" {Asset Symbol: "WHYPE"/"USDE"/"USDT"} --rpc-url \
/// https://rpc.hyperliquid.xyz/evm
///
/// forge script PoolCapView --sig "viewPool(uint256)" {Pool ID} --rpc-url \
/// https://rpc.hyperliquid.xyz/evm
contract PoolCapView is BaseScript, Test {
    using Math for uint256;

    // pool
    IPool public pool;

    // Risk Engine
    IRiskEngine public riskEngine;

    // Constants
    address public constant ETH_USD_FEED =
        0x1b27A24642B1a5a3c54452DDc02F278fb6F63229;
    address public constant POOL_ADDRESS =
        0x36BFD6b40e2c9BbCfD36a6B1F1Aa65974f4fFA5D;

    // Keep these constants as reference values only
    uint256 public constant WHYPE_POOL_ID =
        14_778_331_100_793_740_007_929_971_613_900_703_995_604_470_186_100_539_494_274_894_855_699_577_891_585;
    uint256 public constant USDE_POOL_ID =
        35_549_059_506_791_825_930_759_374_493_305_863_417_254_935_666_006_142_339_056_302_529_054_626_325_948;
    uint256 public constant USDT_POOL_ID =
        24_340_067_792_848_736_884_157_565_898_336_136_257_613_434_225_645_880_261_054_440_301_452_940_585_526;

    // ANSI color codes for console output - use escape character for proper display
    string constant RESET = "\x1b[0m";
    string constant RED = "\x1b[31m";
    string constant YELLOW = "\x1b[33m";
    string constant GREEN = "\x1b[32m";

    // Utilization thresholds
    uint256 constant CRITICAL_THRESHOLD = 9000; // 90%
    uint256 constant WARNING_THRESHOLD = 8000; // 80%
    uint256 constant NORMAL_THRESHOLD = 5000; // 50%

    struct PoolCapInfo {
        address asset;
        string symbol;
        uint8 decimals;
        uint256 poolId;
        uint256 totalBorrows;
        uint256 borrowCap;
        uint256 borrowCapUtilization;
        uint256 totalAssets;
        uint256 poolCap;
        uint256 poolCapUtilization;
        uint256 assetsInEth;
        uint256 assetsInUsd;
        uint256 borrowsInEth;
        uint256 borrowsInUsd;
    }

    function run() public {}

    function viewAllPools() public {
        pool = IPool(POOL_ADDRESS);
        riskEngine = IRiskEngine(pool.riskEngine());

        // Use hardcoded pool IDs directly - getAllPoolIds is not implemented
        uint256[] memory poolIds = new uint256[](3);
        poolIds[0] = WHYPE_POOL_ID;
        poolIds[1] = USDE_POOL_ID;
        poolIds[2] = USDT_POOL_ID;

        _displayPoolSummaryHeader(poolIds.length);

        // Display each pool's info
        for (uint256 i = 0; i < poolIds.length; i++) {
            PoolCapInfo memory info = getPoolCapInfo(poolIds[i]);
            _displayPoolSummaryLine(info);
        }

        _displayPoolSummaryFooter();
    }

    // Helper function to display the summary header
    function _displayPoolSummaryHeader(uint256 poolCount) internal pure {
        console2.log("\n=== Protocol Pool Capacity Summary ===");
        console2.log("Total pools: ", poolCount);
        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log(
            "Symbol      | Borrow Amount (% Cap) | Supply Amount (% Cap) | Borrowed (USD) | Supplied (USD)"
        );
        console2.log(
            "--------------------------------------------------------------------------------"
        );
    }

    // Helper function to display a single pool summary line
    function _displayPoolSummaryLine(PoolCapInfo memory info) internal pure {
        // Format utilization with color coding
        string memory borrowUtilStr = _formatColoredPercentage(
            info.borrowCapUtilization
        );
        string memory supplyUtilStr = _formatColoredPercentage(
            info.poolCapUtilization
        );

        // Format borrowed and supplied amounts with correct decimals
        string memory formattedBorrowed = _formatWithDecimals(
            info.totalBorrows,
            info.decimals
        );
        string memory formattedSupplied = _formatWithDecimals(
            info.totalAssets,
            info.decimals
        );

        // Format USD values with K/M suffix for readability
        string memory borrowedUsd = _formatUsdWithSuffix(info.borrowsInUsd);
        string memory suppliedUsd = _formatUsdWithSuffix(info.assetsInUsd);

        // Create the display line with proper spacing
        // Use the correct symbol based on the pool ID
        string memory symbolDisplay = info.symbol;

        // Check pool ID to ensure correct symbol display
        if (info.poolId == WHYPE_POOL_ID) {
            symbolDisplay = "WHYPE";
        } else if (info.poolId == USDE_POOL_ID) {
            symbolDisplay = "USDE";
        } else if (info.poolId == USDT_POOL_ID) {
            symbolDisplay = "USDT";
        }

        console2.log(
            string.concat(
                _padRight(symbolDisplay, 11),
                "| ",
                _padRight(formattedBorrowed, 12),
                " (",
                _padRight(borrowUtilStr, 6),
                ") | ",
                _padRight(formattedSupplied, 12),
                " (",
                _padRight(supplyUtilStr, 6),
                ") | ",
                _padRight(borrowedUsd, 13),
                " | ",
                _padRight(suppliedUsd, 13)
            )
        );
    }

    // Helper function to display the summary footer
    function _displayPoolSummaryFooter() internal pure {
        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log(
            string.concat(
                "Color coding: ",
                RED,
                "#",
                RESET,
                " >90%, ",
                YELLOW,
                "#",
                RESET,
                " >80%, ",
                GREEN,
                "#",
                RESET,
                " >50%, ",
                "# <50%"
            )
        );
        console2.log("\nRun with specific pool symbol for detailed view.");
    }

    function viewPool(uint256 poolId) public {
        pool = IPool(POOL_ADDRESS);
        riskEngine = IRiskEngine(pool.riskEngine());

        PoolCapInfo memory info = getPoolCapInfo(poolId);
        _displayPoolDetailedInfo(info);
    }

    function viewPool(string memory assetSymbol) public {
        uint256 poolId = getPoolIdFromSymbol(assetSymbol);
        viewPool(poolId);
    }

    /// @notice Compare multiple pools side by side
    /// @dev Usage: `forge script PoolCapView --sig "comparePools(string[])" '["WHYPE","USDE","USDT"]' --rpc-url https://rpc.hyperliquid.xyz/evm`
    /// @param symbols Array of asset symbols to compare
    function comparePools(string[] memory symbols) public {
        pool = IPool(POOL_ADDRESS);
        riskEngine = IRiskEngine(pool.riskEngine());

        uint256[] memory poolIds = new uint256[](symbols.length);
        PoolCapInfo[] memory pools = new PoolCapInfo[](symbols.length);

        // First collect all pool data
        for (uint256 i = 0; i < symbols.length; i++) {
            poolIds[i] = getPoolIdFromSymbol(symbols[i]);
            pools[i] = getPoolCapInfo(poolIds[i]);

            // Force refresh of data for WHYPE pool if it's showing zero values
            if (poolIds[i] == WHYPE_POOL_ID && pools[i].totalBorrows == 0) {
                try pool.getTotalBorrows(poolIds[i]) returns (uint256 borrows) {
                    pools[i].totalBorrows = borrows;
                } catch {}

                try pool.getTotalAssets(poolIds[i]) returns (uint256 assets) {
                    pools[i].totalAssets = assets;
                } catch {}

                // Recalculate utilization percentages
                pools[i].borrowCapUtilization = pools[i].borrowCap > 0
                    ? pools[i].totalBorrows.mulDiv(
                        10000,
                        pools[i].borrowCap,
                        Math.Rounding.Up
                    )
                    : 0;
                pools[i].poolCapUtilization = pools[i].poolCap > 0
                    ? pools[i].totalAssets.mulDiv(
                        10000,
                        pools[i].poolCap,
                        Math.Rounding.Up
                    )
                    : 0;

                // Recalculate values in ETH and USD
                pools[i].assetsInEth = _getValueInEth(
                    pools[i].asset,
                    pools[i].totalAssets
                );
                pools[i].borrowsInEth = _getValueInEth(
                    pools[i].asset,
                    pools[i].totalBorrows
                );
                pools[i].assetsInUsd = ethToUsd(pools[i].assetsInEth);
                pools[i].borrowsInUsd = ethToUsd(pools[i].borrowsInEth);
            }
        }

        // Print header and symbols
        _displayComparisonHeader(pools);

        // Display different metrics
        _displayBorrowMetrics(pools);
        _displaySupplyMetrics(pools);
        _displayCapacityMetrics(pools);

        // Display footer
        console2.log(
            "-------------------------------------------------------------------------"
        );
        console2.log(
            string.concat(
                "Color coding: ",
                RED,
                "#",
                RESET,
                " >90%, ",
                YELLOW,
                "#",
                RESET,
                " >80%, ",
                GREEN,
                "#",
                RESET,
                " >50%, ",
                "# <50%"
            )
        );
    }

    // Helper function to display comparison header
    function _displayComparisonHeader(
        PoolCapInfo[] memory pools
    ) internal pure {
        // Print header
        console2.log("\n=== Pool Comparison ===");
        console2.log(
            "------------------------------------------------------------------------------"
        );

        // Print symbols with proper alignment
        string memory symbolLine = _padRight("Metrics", 14);
        for (uint256 i = 0; i < pools.length; i++) {
            // Use the correct symbol based on the pool ID
            string memory symbolDisplay = pools[i].symbol;

            if (pools[i].poolId == WHYPE_POOL_ID) {
                symbolDisplay = "WHYPE";
            } else if (pools[i].poolId == USDE_POOL_ID) {
                symbolDisplay = "USDE";
            } else if (pools[i].poolId == USDT_POOL_ID) {
                symbolDisplay = "USDT";
            }

            symbolLine = string.concat(
                symbolLine,
                " | ",
                _centerText(symbolDisplay, 14)
            );
        }
        console2.log(symbolLine);
        console2.log(
            "------------------------------------------------------------------------------"
        );
    }

    // Helper function to display borrow metrics
    function _displayBorrowMetrics(PoolCapInfo[] memory pools) internal pure {
        // Print borrow utilization with actual values
        string memory borrowLine = _padRight("Borrowed", 14);
        for (uint256 i = 0; i < pools.length; i++) {
            string memory formattedBorrowed = _formatWithDecimals(
                pools[i].totalBorrows,
                pools[i].decimals
            );
            borrowLine = string.concat(
                borrowLine,
                " | ",
                _padRight(formattedBorrowed, 14)
            );
        }
        console2.log(borrowLine);

        // Print borrow utilization with percentages
        string memory borrowUtilLine = _padRight("Borrow %", 14);
        for (uint256 i = 0; i < pools.length; i++) {
            borrowUtilLine = string.concat(
                borrowUtilLine,
                " | ",
                _centerText(
                    _formatColoredPercentage(pools[i].borrowCapUtilization),
                    14
                )
            );
        }
        console2.log(borrowUtilLine);
    }

    // Helper function to display supply metrics
    function _displaySupplyMetrics(PoolCapInfo[] memory pools) internal pure {
        // Print supply utilization with actual values
        string memory supplyLine = _padRight("Supplied", 14);
        for (uint256 i = 0; i < pools.length; i++) {
            string memory formattedSupplied = _formatWithDecimals(
                pools[i].totalAssets,
                pools[i].decimals
            );
            supplyLine = string.concat(
                supplyLine,
                " | ",
                _padRight(formattedSupplied, 14)
            );
        }
        console2.log(supplyLine);

        // Print supply utilization with percentages
        string memory supplyUtilLine = _padRight("Supply %", 14);
        for (uint256 i = 0; i < pools.length; i++) {
            supplyUtilLine = string.concat(
                supplyUtilLine,
                " | ",
                _centerText(
                    _formatColoredPercentage(pools[i].poolCapUtilization),
                    14
                )
            );
        }
        console2.log(supplyUtilLine);
    }

    // Helper function to display capacity metrics
    function _displayCapacityMetrics(PoolCapInfo[] memory pools) internal view {
        _displayCapValues(pools);
        _displayRemainingCapacity(pools);
    }

    // Helper function to display cap values
    function _displayCapValues(PoolCapInfo[] memory pools) internal view {
        // Print borrow caps in USD
        string memory borrowCapLine = _padRight("Borrow Cap", 14);
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 borrowCapInEth = _getValueInEth(
                pools[i].asset,
                pools[i].borrowCap
            );
            uint256 borrowCapInUsd = ethToUsd(borrowCapInEth);

            borrowCapLine = string.concat(
                borrowCapLine,
                " | ",
                _centerText(_formatUsdWithSuffix(borrowCapInUsd), 14)
            );
        }
        console2.log(borrowCapLine);

        // Print supply caps in USD
        string memory supplyCapLine = _padRight("Supply Cap", 14);
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 supplyCapInEth = _getValueInEth(
                pools[i].asset,
                pools[i].poolCap
            );
            uint256 supplyCapInUsd = ethToUsd(supplyCapInEth);

            supplyCapLine = string.concat(
                supplyCapLine,
                " | ",
                _centerText(_formatUsdWithSuffix(supplyCapInUsd), 14)
            );
        }
        console2.log(supplyCapLine);
    }

    // Helper function to display remaining capacity
    function _displayRemainingCapacity(
        PoolCapInfo[] memory pools
    ) internal view {
        // Print remaining borrow capacity
        string memory remainingBorrowLine = _padRight("Remain Borrow", 14);
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 remainingBorrows = 0;
            if (pools[i].borrowCap > pools[i].totalBorrows) {
                remainingBorrows = pools[i].borrowCap - pools[i].totalBorrows;
            }

            uint256 remainingInEth = _getValueInEth(
                pools[i].asset,
                remainingBorrows
            );
            uint256 remainingInUsd = ethToUsd(remainingInEth);

            string memory value;
            if (remainingBorrows == 0) {
                value = string.concat(RED, "0", RESET);
            } else {
                value = _formatUsdWithSuffix(remainingInUsd);
            }

            remainingBorrowLine = string.concat(
                remainingBorrowLine,
                " | ",
                _centerText(value, 14)
            );
        }
        console2.log(remainingBorrowLine);

        // Print remaining supply capacity
        string memory remainingSupplyLine = _padRight("Remain Supply", 14);
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 remainingSupply = 0;
            if (pools[i].poolCap > pools[i].totalAssets) {
                remainingSupply = pools[i].poolCap - pools[i].totalAssets;
            }

            uint256 remainingInEth = _getValueInEth(
                pools[i].asset,
                remainingSupply
            );
            uint256 remainingInUsd = ethToUsd(remainingInEth);

            string memory value;
            if (remainingSupply == 0) {
                value = string.concat(RED, "0", RESET);
            } else {
                value = _formatUsdWithSuffix(remainingInUsd);
            }

            remainingSupplyLine = string.concat(
                remainingSupplyLine,
                " | ",
                _centerText(value, 14)
            );
        }
        console2.log(remainingSupplyLine);
    }

    /// @notice Convert asset symbol to pool ID
    /// @param symbol The asset symbol (WHYPE, USDE, USDT)
    /// @return poolId The corresponding pool ID
    function getPoolIdFromSymbol(
        string memory symbol
    ) public pure returns (uint256 poolId) {
        bytes32 symbolHash = keccak256(abi.encodePacked(symbol));

        if (symbolHash == keccak256(abi.encodePacked("WHYPE"))) {
            return WHYPE_POOL_ID;
        } else if (symbolHash == keccak256(abi.encodePacked("USDE"))) {
            return USDE_POOL_ID;
        } else if (symbolHash == keccak256(abi.encodePacked("USDT"))) {
            return USDT_POOL_ID;
        }

        revert("Unknown asset symbol");
    }

    function getPoolCapInfo(
        uint256 poolId
    ) public view returns (PoolCapInfo memory info) {
        address asset = pool.getPoolAssetFor(poolId);

        // Get asset metadata
        string memory symbol = _getTokenSymbol(asset);
        uint8 decimals = _getTokenDecimals(asset);

        // Get pool data - with error handling
        uint256 totalBorrows;
        uint256 totalAssets;

        try pool.getTotalBorrows(poolId) returns (uint256 borrows) {
            totalBorrows = borrows;
        } catch {
            // If there's an error (like arithmetic overflow), use a fallback
            totalBorrows = 0;
        }

        try pool.getTotalAssets(poolId) returns (uint256 assets) {
            totalAssets = assets;
        } catch {
            // If there's an error, use a fallback
            totalAssets = 0;
        }

        uint256 borrowCap = pool.getBorrowCapFor(poolId);
        uint256 poolCap = pool.getPoolCapFor(poolId);

        // Calculate utilization percentages (scaled by 10000 for basis points)
        uint256 borrowCapUtilization = borrowCap > 0
            ? totalBorrows.mulDiv(10000, borrowCap, Math.Rounding.Up)
            : 0;
        uint256 poolCapUtilization = poolCap > 0
            ? totalAssets.mulDiv(10000, poolCap, Math.Rounding.Up)
            : 0;

        // Calculate values in ETH and USD
        uint256 assetsInEth = _getValueInEth(asset, totalAssets);
        uint256 borrowsInEth = _getValueInEth(asset, totalBorrows);

        return
            PoolCapInfo({
                asset: asset,
                symbol: symbol,
                decimals: decimals,
                poolId: poolId,
                totalBorrows: totalBorrows,
                borrowCap: borrowCap,
                borrowCapUtilization: borrowCapUtilization,
                totalAssets: totalAssets,
                poolCap: poolCap,
                poolCapUtilization: poolCapUtilization,
                assetsInEth: assetsInEth,
                assetsInUsd: ethToUsd(assetsInEth),
                borrowsInEth: borrowsInEth,
                borrowsInUsd: ethToUsd(borrowsInEth)
            });
    }

    function _displayPoolDetailedInfo(PoolCapInfo memory info) internal view {
        console2.log("\n=== Pool Cap Details ===");
        console2.log(string.concat("Pool ID: ", vm.toString(info.poolId)));
        console2.log(string.concat("Asset: ", vm.toString(info.asset)));
        console2.log(string.concat("Symbol: ", info.symbol));
        console2.log(string.concat("Decimals: ", vm.toString(info.decimals)));
        console2.log("-----------------------------------------------------");

        // Display borrow information
        _displayBorrowInfo(info);

        // Display supply information
        console2.log("-----------------------------------------------------");
        _displaySupplyInfo(info);
    }

    // Helper function to display borrow information
    function _displayBorrowInfo(PoolCapInfo memory info) internal view {
        // Format with correct decimals
        string memory formattedTotalBorrows = _formatWithDecimals(
            info.totalBorrows,
            info.decimals
        );
        string memory formattedBorrowCap = _formatWithDecimals(
            info.borrowCap,
            info.decimals
        );

        // Format USD values
        string memory borrowsUsd = _formatUsdWithSuffix(info.borrowsInUsd);

        // Calculate caps in USD
        uint256 borrowCapInEth = _getValueInEth(info.asset, info.borrowCap);
        uint256 borrowCapInUsd = ethToUsd(borrowCapInEth);
        string memory borrowCapUsd = _formatUsdWithSuffix(borrowCapInUsd);

        // Display borrow information
        console2.log(string.concat(GREEN, "BORROW INFORMATION:", RESET));
        console2.log(
            string.concat(
                "Total Borrows: ",
                formattedTotalBorrows,
                " ",
                info.symbol,
                " of ",
                formattedBorrowCap,
                " ",
                info.symbol
            )
        );

        console2.log(
            string.concat("Borrow Value: ", borrowsUsd, " of ", borrowCapUsd)
        );

        // Format colored utilization
        string memory borrowUtilStr = _formatColoredPercentage(
            info.borrowCapUtilization
        );
        console2.log(string.concat("Borrow Utilization: ", borrowUtilStr));

        // Show remaining capacity
        _displayRemainingBorrowCapacity(info);
    }

    // Helper function to display remaining borrow capacity
    function _displayRemainingBorrowCapacity(
        PoolCapInfo memory info
    ) internal view {
        if (info.borrowCap > info.totalBorrows) {
            uint256 remainingBorrows = info.borrowCap - info.totalBorrows;
            string memory formattedRemainingBorrows = _formatWithDecimals(
                remainingBorrows,
                info.decimals
            );

            // Calculate remaining in USD
            uint256 remainingInEth = _getValueInEth(
                info.asset,
                remainingBorrows
            );
            uint256 remainingInUsd = ethToUsd(remainingInEth);
            string memory remainingUsd = _formatUsdWithSuffix(remainingInUsd);

            console2.log(
                string.concat(
                    "Remaining Borrow Capacity: ",
                    formattedRemainingBorrows,
                    " ",
                    info.symbol,
                    " (",
                    remainingUsd,
                    ")"
                )
            );
        } else {
            console2.log(string.concat(RED, "Borrow Cap Reached!", RESET));
        }
    }

    // Helper function to display supply information
    function _displaySupplyInfo(PoolCapInfo memory info) internal view {
        // Format with correct decimals
        string memory formattedTotalAssets = _formatWithDecimals(
            info.totalAssets,
            info.decimals
        );
        string memory formattedPoolCap = _formatWithDecimals(
            info.poolCap,
            info.decimals
        );

        // Format USD values
        string memory assetsUsd = _formatUsdWithSuffix(info.assetsInUsd);

        // Calculate caps in USD
        uint256 supplyCapInEth = _getValueInEth(info.asset, info.poolCap);
        uint256 supplyCapInUsd = ethToUsd(supplyCapInEth);
        string memory supplyCapUsd = _formatUsdWithSuffix(supplyCapInUsd);

        // Display supply information
        console2.log(string.concat(GREEN, "SUPPLY INFORMATION:", RESET));
        console2.log(
            string.concat(
                "Total Assets: ",
                formattedTotalAssets,
                " ",
                info.symbol,
                " of ",
                formattedPoolCap,
                " ",
                info.symbol
            )
        );

        console2.log(
            string.concat("Supply Value: ", assetsUsd, " of ", supplyCapUsd)
        );

        // Format colored utilization
        string memory supplyUtilStr = _formatColoredPercentage(
            info.poolCapUtilization
        );
        console2.log(string.concat("Supply Utilization: ", supplyUtilStr));

        // Show remaining capacity
        _displayRemainingSupplyCapacity(info);
    }

    // Helper function to display remaining supply capacity
    function _displayRemainingSupplyCapacity(
        PoolCapInfo memory info
    ) internal view {
        if (info.poolCap > info.totalAssets) {
            uint256 remainingSupply = info.poolCap - info.totalAssets;
            string memory formattedRemainingSupply = _formatWithDecimals(
                remainingSupply,
                info.decimals
            );

            // Calculate remaining in USD
            uint256 remainingInEth = _getValueInEth(
                info.asset,
                remainingSupply
            );
            uint256 remainingInUsd = ethToUsd(remainingInEth);
            string memory remainingUsd = _formatUsdWithSuffix(remainingInUsd);

            console2.log(
                string.concat(
                    "Remaining Supply Capacity: ",
                    formattedRemainingSupply,
                    " ",
                    info.symbol,
                    " (",
                    remainingUsd,
                    ")"
                )
            );
        } else {
            console2.log(string.concat(RED, "Supply Cap Reached!", RESET));
        }
    }

    function _getValueInEth(
        address asset,
        uint256 amt
    ) internal view returns (uint256) {
        IOracle oracle = IOracle(riskEngine.oracleFor(asset));

        // oracles could revert, but lens calls must not
        try oracle.getValueInEth(asset, amt) returns (uint256 valueInEth) {
            return valueInEth;
        } catch {
            return 0;
        }
    }

    function ethToUsd(uint256 amt) public view returns (uint256 usd) {
        (, int256 answer, , , ) = IAggregatorV3(ETH_USD_FEED).latestRoundData();
        usd = amt.mulDiv(uint256(answer), 1e8);
    }

    /// @notice Get the token symbol safely
    function _getTokenSymbol(
        address tokenAddress
    ) internal view returns (string memory) {
        try IERC20Metadata(tokenAddress).symbol() returns (
            string memory symbol
        ) {
            return symbol;
        } catch {
            return "Unknown";
        }
    }

    /// @notice Helper function to get token decimals from ERC20 tokens
    /// @param tokenAddress The address of the token
    /// @return decimals The number of decimals the token uses, defaults to 18 if call fails
    function _getTokenDecimals(
        address tokenAddress
    ) internal view returns (uint8 decimals) {
        try IERC20Metadata(tokenAddress).decimals() returns (
            uint8 tokenDecimals
        ) {
            return tokenDecimals;
        } catch {
            // If the call fails, default to 18 decimals
            return 18;
        }
    }

    /// @notice Format a token amount with proper decimals for human-readable output
    /// @param amount The raw token amount
    /// @param decimals The token's decimal places
    /// @return result The formatted string with proper decimal representation
    function _formatWithDecimals(
        uint256 amount,
        uint8 decimals
    ) internal pure returns (string memory result) {
        if (amount == 0) return "0";

        // First convert to a string
        string memory amountStr = vm.toString(amount);
        bytes memory amountBytes = bytes(amountStr);

        // If the length is less than or equal to decimals, we need to pad with leading zeros
        if (amountBytes.length <= decimals) {
            // Create the fractional part with appropriate padding
            string memory fractionalPart = "";
            for (uint8 i = 0; i < decimals - amountBytes.length; i++) {
                fractionalPart = string(abi.encodePacked(fractionalPart, "0"));
            }
            fractionalPart = string(
                abi.encodePacked(fractionalPart, amountStr)
            );
            return string(abi.encodePacked("0.", fractionalPart));
        } else {
            // Split into integer and fractional parts
            uint8 integerLength = uint8(amountBytes.length) - decimals;

            // Extract integer part
            bytes memory integerBytes = new bytes(integerLength);
            for (uint8 i = 0; i < integerLength; i++) {
                integerBytes[i] = amountBytes[i];
            }

            // Extract fractional part if any
            string memory fractionalPart = "";
            if (decimals > 0) {
                // Only show 2 decimal places for better readability
                uint8 displayDecimals = decimals >= 2 ? 2 : decimals;
                bytes memory fractionalBytes = new bytes(displayDecimals);
                for (uint8 i = 0; i < displayDecimals; i++) {
                    fractionalBytes[i] = amountBytes[integerLength + i];
                }
                fractionalPart = string(
                    abi.encodePacked(".", string(fractionalBytes))
                );
            }

            return
                string(abi.encodePacked(string(integerBytes), fractionalPart));
        }
    }

    /// @notice Format a percentage value with 2 decimal places (from basis points)
    /// @param basisPoints The percentage value in basis points (10000 = 100%)
    /// @return result The formatted percentage string with proper decimal representation
    function _formatPercentage(
        uint256 basisPoints
    ) internal pure returns (string memory result) {
        // Extract whole number part and decimal part
        uint256 wholeNumber = basisPoints / 100;
        uint256 decimalPart = basisPoints % 100;

        // Format decimal part with leading zero if needed
        string memory decimalStr = vm.toString(decimalPart);
        if (decimalPart < 10) {
            decimalStr = string.concat("0", decimalStr);
        }

        return string.concat(vm.toString(wholeNumber), ".", decimalStr, "%");
    }

    /// @notice Format a percentage value with color coding based on utilization level
    /// @param basisPoints The percentage value in basis points (10000 = 100%)
    /// @return result The formatted percentage string with ANSI color coding
    function _formatColoredPercentage(
        uint256 basisPoints
    ) internal pure returns (string memory) {
        string memory color;

        // Select color based on utilization level
        if (basisPoints >= CRITICAL_THRESHOLD) {
            color = RED;
        } else if (basisPoints >= WARNING_THRESHOLD) {
            color = YELLOW;
        } else if (basisPoints >= NORMAL_THRESHOLD) {
            color = GREEN;
        } else {
            color = RESET;
        }

        // Format the percentage
        string memory percentageStr = _formatPercentage(basisPoints);

        // Return colored percentage
        return string.concat(color, percentageStr, RESET);
    }

    // Helper functions for string formatting
    /// @notice Pad a string to the right with spaces to reach the desired length
    /// @param str The input string
    /// @param length The desired length
    /// @return The padded string
    function _padRight(
        string memory str,
        uint256 length
    ) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= length) return str;

        uint256 paddingNeeded = length - strBytes.length;
        string memory padding = "";
        for (uint256 i = 0; i < paddingNeeded; i++) {
            padding = string.concat(padding, " ");
        }

        return string.concat(str, padding);
    }

    /// @notice Add spaces before and after a string to center it within a fixed width
    /// @param str The input string
    /// @param length The desired total length
    /// @return The centered string
    function _centerText(
        string memory str,
        uint256 length
    ) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= length) return str;

        uint256 paddingNeeded = length - strBytes.length;
        uint256 leftPadding = paddingNeeded / 2;
        uint256 rightPadding = paddingNeeded - leftPadding;

        string memory leftPad = "";
        for (uint256 i = 0; i < leftPadding; i++) {
            leftPad = string.concat(leftPad, " ");
        }

        string memory rightPad = "";
        for (uint256 i = 0; i < rightPadding; i++) {
            rightPad = string.concat(rightPad, " ");
        }

        return string.concat(leftPad, str, rightPad);
    }

    // Add a function to format USD values with K/M/B suffix for readability
    function _formatUsdWithSuffix(
        uint256 usdValue
    ) internal pure returns (string memory) {
        uint256 value = usdValue / 1e18; // Convert from wei to whole units

        if (value >= 1_000_000_000) {
            // Billions
            uint256 billions = value / 1_000_000_000;
            uint256 remainder = (value % 1_000_000_000) / 10_000_000; // Get 2 decimal places
            if (remainder == 0) {
                return string.concat(vm.toString(billions), "B");
            } else {
                string memory decimalPart = vm.toString(remainder);
                // Pad with leading zero if needed
                if (remainder < 10) {
                    decimalPart = string.concat("0", decimalPart);
                }
                return
                    string.concat(vm.toString(billions), ".", decimalPart, "B");
            }
        } else if (value >= 1_000_000) {
            // Millions
            uint256 millions = value / 1_000_000;
            uint256 remainder = (value % 1_000_000) / 10_000; // Get 2 decimal places
            if (remainder == 0) {
                return string.concat(vm.toString(millions), "M");
            } else {
                string memory decimalPart = vm.toString(remainder);
                // Pad with leading zero if needed
                if (remainder < 10) {
                    decimalPart = string.concat("0", decimalPart);
                }
                return
                    string.concat(vm.toString(millions), ".", decimalPart, "M");
            }
        } else if (value >= 1_000) {
            // Thousands
            uint256 thousands = value / 1_000;
            uint256 remainder = (value % 1_000) / 10; // Get 2 decimal places
            if (remainder == 0) {
                return string.concat(vm.toString(thousands), "K");
            } else {
                string memory decimalPart = vm.toString(remainder);
                // Pad with leading zero if needed
                if (remainder < 10) {
                    decimalPart = string.concat("0", decimalPart);
                }
                return
                    string.concat(
                        vm.toString(thousands),
                        ".",
                        decimalPart,
                        "K"
                    );
            }
        } else {
            // Less than 1000
            return string.concat(vm.toString(value));
        }
    }
}
