// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseScript} from "../BaseScript.s.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IOracle} from "src/interfaces/IOracle.sol";
import {IRateModel} from "src/interfaces/IRateModel.sol";

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

interface ISuperPool {
    function POOL() external view returns (address);
    function decimals() external view returns (uint8);
    function name() external view returns (string memory);
    function paused() external view returns (bool);
    function asset() external view returns (IERC20);
    function owner() external view returns (address);
    function feeRecipient() external view returns (address);
    function fee() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function superPoolCap() external view returns (uint256);
    function pools() external view returns (uint256[] memory);
    function withdrawQueue(uint256 index) external view returns (uint256);
}

interface IRiskEngine {
    function oracleFor(address asset) external view returns (address);
    function riskModule() external view returns (address);
    function getRiskData(
        address position
    )
        external
        view
        returns (
            uint256 totalAssetValue,
            uint256 totalDebtValue,
            uint256 weightedLtv
        );
}

interface IRiskModule {
    function getPositionHealthFactor(
        address position
    ) external view returns (uint256);
}

interface IPosition {
    function POOL() external view returns (address);
    function RISK_ENGINE() external view returns (address);
    function getDebtPools() external view returns (uint256[] memory);
    function getPositionAssets() external view returns (address[] memory);
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
/// forge script RiskView --sig "getSuperPoolData(address)" {SuperPool address} --rpc-url \
/// https://rpc.hyperliquid.xyz/evm
/// forge script RiskView --sig "getPoolData(address)" {Pool address} --rpc-url \
/// https://rpc.hyperliquid.xyz/evm
/// forge script RiskView --sig "getPositionData(address)" {Position address} --rpc-url \
/// https://rpc.hyperliquid.xyz/evm
/// forge script RiskView --sig "getHistoricNav(address,uint256)" {Position address} {# of Historical Days} \
/// --rpc-url https://rpc.hyperliquid.xyz/evm
contract RiskView is BaseScript, Test {
    using Math for uint256;

    // pool
    IPool public pool;

    // superPool
    ISuperPool public superPool;

    // Risk Engine
    IRiskEngine public riskEngine;

    // Risk Module
    IRiskModule public riskModule;

    // Position
    IPosition public position;

    address public constant ETH_USD_FEED =
        0x1b27A24642B1a5a3c54452DDc02F278fb6F63229;

    mapping(address pool => uint256 poolId) public poolMap;
    address[] private _collateralAssets;

    struct SuperPoolData {
        address pool;
        uint8 decimals;
        string name;
        bool isPaused;
        address asset;
        address owner;
        address feeRecipient;
        uint256 fee;
        uint256 idleAssets;
        uint256 idleAssetsUsd;
        uint256 totalAssets;
        uint256 totalAssetsUsd;
        uint256 supplyRate;
        uint256 superPoolCap;
        uint256[] depositQueue;
        uint256[] withdrawQueue;
        PoolDepositData[] poolDepositData;
    }

    struct PoolDepositData {
        address asset;
        uint256 poolId;
        uint256 borrowInterestRate;
        uint256 supplyInterestRate;
    }

    function run() public {}

    // @dev Add hardcoded mainnet deployed pool ids and collateral assets here
    function _run() internal {
        // pool address => poolId
        poolMap[
            0x36BFD6b40e2c9BbCfD36a6B1F1Aa65974f4fFA5D
        ] = 14_778_331_100_793_740_007_929_971_613_900_703_995_604_470_186_100_539_494_274_894_855_699_577_891_585;
        _collateralAssets.push(0x94e8396e0869c9F2200760aF0621aFd240E1CF38); // wstHype
    }

    function getSuperPoolData(address superPool_) public {
        _run();

        superPool = ISuperPool(superPool_);
        pool = IPool(superPool.POOL());
        riskEngine = IRiskEngine(pool.riskEngine());

        uint256[] memory pools = superPool.pools(); // fetch underlying pools for given super pool

        // fetch data for each underlying pool
        uint256 poolsLength = pools.length;
        PoolDepositData[] memory deposits = new PoolDepositData[](poolsLength);
        uint256[] memory withdrawQueue = new uint256[](pools.length);
        for (uint256 i; i < poolsLength; ++i) {
            deposits[i] = getPoolDepositData(pools[i]);
            withdrawQueue[i] = superPool.withdrawQueue(i);
        }

        // aggregate data from underlying pools
        address asset = address(superPool.asset());
        uint256 totalAssets = superPool.totalAssets();

        SuperPoolData memory superPoolData = SuperPoolData({
            decimals: superPool.decimals(),
            pool: superPool_,
            name: superPool.name(),
            isPaused: superPool.paused(),
            asset: asset,
            owner: superPool.owner(),
            feeRecipient: superPool.feeRecipient(),
            fee: superPool.fee(),
            idleAssets: IERC20(asset).balanceOf(superPool_),
            idleAssetsUsd: ethToUsd(
                _getValueInEth(asset, IERC20(asset).balanceOf(superPool_)) /
                    1e18
            ),
            totalAssets: totalAssets,
            totalAssetsUsd: ethToUsd(_getValueInEth(asset, totalAssets) / 1e18),
            supplyRate: getSuperPoolInterestRate(superPool_),
            superPoolCap: superPool.superPoolCap(),
            depositQueue: superPool.pools(),
            withdrawQueue: withdrawQueue,
            poolDepositData: deposits
        });

        console2.log("superPool address: ", superPoolData.pool);
        console2.log("decimals: ", superPoolData.decimals);
        console2.log("name: ", superPoolData.name);
        console2.log("isPaused: ", superPoolData.isPaused);
        console2.log("asset: ", superPoolData.asset);
        console2.log("owner: ", superPoolData.owner);
        console2.log("feeRecipient: ", superPoolData.feeRecipient);
        console2.log("fee: ", superPoolData.fee, "USD");
        console2.log(
            "idleAssets: ",
            superPoolData.idleAssets / 1e18,
            IERC20(superPoolData.asset).symbol()
        );
        console2.log("idleAssetsUsd: ", superPoolData.idleAssetsUsd, "USD");
        console2.log(
            "totalAssets: ",
            superPoolData.totalAssets / 1e18,
            IERC20(superPoolData.asset).symbol()
        );
        console2.log("totalAssetsUsd: ", superPoolData.totalAssetsUsd, "USD");
        console2.log("supplyRate: %4e%", superPoolData.supplyRate / 1e12);
        console2.log(
            "superPoolCap: ",
            superPoolData.superPoolCap / 1e18,
            IERC20(superPoolData.asset).symbol()
        );
        console2.log(
            "superPool utilization rate: %2e%",
            getSuperPoolUtilizationRate() / 1e14
        );
        console2.log("");
        console2.log("depositQueue: ");
        emit log_array(superPoolData.depositQueue);
        console2.log("");
        console2.log("withdrawQueue: ");
        emit log_array(superPoolData.withdrawQueue);
        console2.log("");
        console2.log("poolDepositData: ");
        for (uint256 i = 0; i < poolsLength; ++i) {
            uint256 amount = pool.getAssetsOf(deposits[i].poolId, superPool_);
            uint256 valueInEth = _getValueInEth(deposits[i].asset, amount);
            console2.log("pool #: ", i + 1);
            console2.log("asset: ", deposits[i].asset);
            console2.log("poolId: ", deposits[i].poolId);
            console2.log(
                "rateModel: ",
                pool.getRateModelFor(deposits[i].poolId)
            );
            console2.log(
                "amount of superPool assets deposited: ",
                amount / 1e18,
                IERC20(superPoolData.asset).symbol()
            );
            console2.log(
                "valueInEth of superPool deposited assets: ",
                valueInEth / 1e18,
                "ETH"
            );
            console2.log("valueInUsd: ", ethToUsd(valueInEth) / 1e18, "USD");
            console2.log(
                "borrowRate: %4e%",
                deposits[i].borrowInterestRate / 1e12
            );
            console2.log(
                "supplyRate: %4e%",
                deposits[i].supplyInterestRate / 1e12
            );
            console2.log(
                "totalBorrows: ",
                pool.getTotalBorrows(deposits[i].poolId) / 1e18,
                IERC20(superPoolData.asset).symbol()
            );
            console2.log(
                "pool borrow cap: ",
                pool.getBorrowCapFor(deposits[i].poolId) / 1e18,
                IERC20(superPoolData.asset).symbol()
            );
            console2.log(
                "total supplied: ",
                pool.getTotalAssets(deposits[i].poolId) / 1e18,
                IERC20(superPoolData.asset).symbol()
            );
            console2.log(
                "pool supply cap: ",
                pool.getPoolCapFor(deposits[i].poolId) / 1e18,
                IERC20(superPoolData.asset).symbol()
            );
            console2.log(
                "pool utilization rate: %2e%",
                getPoolUtilizationRate(deposits[i].poolId) / 1e14
            );
        }
        console2.log("");
        console2.log("oracles:");
        console2.log("borrowAsset: ", superPoolData.asset);
        console2.log(
            "oracle addr: ",
            riskEngine.oracleFor(superPoolData.asset)
        );
        console2.log(
            "oracle eth price: %18e",
            _getValueInEth(superPoolData.asset, 1e18),
            "ETH"
        );
        console2.log(
            "oracle usd price: %2e",
            ethToUsd(_getValueInEth(superPoolData.asset, 1e18)) / 1e16,
            "USD"
        );

        for (uint256 i = 0; i < _collateralAssets.length; ++i) {
            console2.log("collateralAsset: ", _collateralAssets[i]);
            console2.log(
                "oracle addr: ",
                riskEngine.oracleFor(_collateralAssets[i])
            );
            console2.log(
                "oracle eth price: %18e",
                _getValueInEth(_collateralAssets[i], 1e18),
                "ETH"
            );
            console2.log(
                "oracle usd price: %2e",
                ethToUsd(_getValueInEth(_collateralAssets[i], 1e18)) / 1e16,
                "USD"
            );
        }
    }

    function getPoolData(address pool_) public {
        _run();

        pool = IPool(pool_);
        uint256 poolId = poolMap[pool_];
        riskEngine = IRiskEngine(pool.riskEngine());

        console2.log("Pool: ", pool_);
        console2.log("asset: ", pool.getPoolAssetFor(poolId));
        console2.log("poolId: ", poolId);
        console2.log("borrowRate: %4e%", getPoolBorrowRate(poolId) / 1e12);
        console2.log("supplyRate: %4e%", getPoolSupplyRate(poolId) / 1e12);
    }

    function getPositionData(address position_) public {
        _run();

        position = IPosition(position_);
        pool = IPool(position.POOL());
        riskEngine = IRiskEngine(position.RISK_ENGINE());
        riskModule = IRiskModule(riskEngine.riskModule());

        console2.log("Position:", position_);
        console2.log("debtPools: ");
        uint256[] memory debtPools = position.getDebtPools();
        emit log_array(debtPools);
        console2.log("collateral assets: ");
        address[] memory positionAssets = position.getPositionAssets();
        emit log_array(positionAssets);
        console2.log(
            "debtAsset: ",
            pool.getPoolAssetFor(poolMap[address(pool)])
        );

        (
            uint256 totalAssetValue,
            uint256 totalDebtValue,
            uint256 weightedLtv
        ) = riskEngine.getRiskData(position_);
        console2.log("*getRiskData*");
        console2.log("totalAssetValue: ");
        console2.log(
            "%4e ETH, %2e USD",
            totalAssetValue / 1e14,
            ethToUsd(totalAssetValue) / 1e16
        );
        console2.log("collateral asset balances:");
        for (uint256 i = 0; i < positionAssets.length; ++i) {
            console2.log(
                "asset: %o, balance: %2e",
                positionAssets[i],
                IERC20(positionAssets[i]).balanceOf(position_) / 1e16
            );
        }
        console2.log("totalDebtValue: ");
        console2.log(
            "%4e ETH, %2e USD",
            totalDebtValue / 1e14,
            ethToUsd(totalDebtValue) / 1e16
        );
        console2.log("debt asset balances:");
        for (uint256 i = 0; i < debtPools.length; ++i) {
            console2.log(
                "asset: %o, balance: %2e",
                pool.getPoolAssetFor(debtPools[i]),
                pool.getBorrowsOf(debtPools[i], position_) / 1e16
            );
        }
        console2.log(
            "current position ltv: %4e",
            (totalDebtValue * 1e18) / totalAssetValue / 1e14
        );
        console2.log("weightedLtv: ");
        console2.log("%4e", weightedLtv / 1e14);
        console2.log(
            "position healthFactor: %4e",
            riskModule.getPositionHealthFactor(position_) / 1e14
        );
    }

    function getPoolDepositData(
        uint256 poolId
    ) public view returns (PoolDepositData memory poolDepositData) {
        address asset = pool.getPoolAssetFor(poolId);

        poolDepositData = PoolDepositData({
            asset: asset,
            poolId: poolId,
            borrowInterestRate: getPoolBorrowRate(poolId),
            supplyInterestRate: getPoolSupplyRate(poolId)
        });
    }

    function getPoolUtilizationRate(
        uint256 poolId
    ) public view returns (uint256 utilizationRate) {
        uint256 totalBorrows = pool.getTotalBorrows(poolId);
        uint256 totalAssets = pool.getTotalAssets(poolId);
        utilizationRate = totalAssets == 0
            ? 0
            : totalBorrows.mulDiv(1e18, totalAssets, Math.Rounding.Up);
    }

    function getSuperPoolUtilizationRate()
        public
        view
        returns (uint256 utilizationRate)
    {
        uint256 totalAssets = superPool.totalAssets();

        if (totalAssets == 0) return 0;
        uint256 totalBorrows;

        uint256[] memory pools = superPool.pools();
        uint256 poolsLength = pools.length;
        for (uint256 i; i < poolsLength; ++i) {
            totalBorrows += pool.getTotalBorrows(pools[i]);
        }

        utilizationRate = totalBorrows == 0
            ? 0
            : totalBorrows.mulDiv(1e18, totalAssets, Math.Rounding.Up);
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

    function getSuperPoolInterestRate(
        address _superPool
    ) public view returns (uint256 weightedInterestRate) {
        uint256 totalAssets = superPool.totalAssets();

        if (totalAssets == 0) return 0;

        uint256[] memory pools = superPool.pools();
        uint256 poolsLength = pools.length;
        for (uint256 i; i < poolsLength; ++i) {
            uint256 assets = pool.getAssetsOf(pools[i], _superPool);
            uint256 utilization = assets.mulDiv(1e18, totalAssets);
            weightedInterestRate += utilization.mulDiv(
                getPoolSupplyRate(pools[i]),
                1e18
            );
        }
    }

    function getPoolBorrowRate(
        uint256 poolId
    ) public view returns (uint256 interestRate) {
        IRateModel irm = IRateModel(pool.getRateModelFor(poolId));
        return
            irm.getInterestRate(
                pool.getTotalBorrows(poolId),
                pool.getTotalAssets(poolId)
            );
    }

    function getPoolSupplyRate(
        uint256 poolId
    ) public view returns (uint256 interestRate) {
        uint256 borrowRate = getPoolBorrowRate(poolId);
        uint256 util = getPoolUtilizationRate(poolId);
        return borrowRate.mulDiv(util, 1e18);
    }

    function ethToUsd(uint256 amt) public view returns (uint256 usd) {
        (, int256 answer, , , ) = IAggregatorV3(ETH_USD_FEED).latestRoundData();
        usd = amt.mulDiv(uint256(answer), 1e8);
    }

    /// @dev Slices a string from startIndex to endIndex (exclusive)
    /// @param str The input string to slice
    /// @param startIndex The start index of the slice (inclusive)
    /// @param endIndex The end index of the slice (exclusive)
    function slice(
        string memory str,
        uint256 startIndex,
        uint256 endIndex
    ) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        require(startIndex < endIndex, "Invalid slice indices");
        require(endIndex <= strBytes.length, "End index out of bounds");

        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = 0; i < endIndex - startIndex; i++) {
            result[i] = strBytes[startIndex + i];
        }
        return string(result);
    }

    /// @dev Generate a string with n zeros
    /// @param n The number of zeros to include in the string
    function _padZeros(uint256 n) internal pure returns (string memory) {
        if (n == 0) return "";

        bytes memory zeros = new bytes(n);
        for (uint256 i = 0; i < n; i++) {
            zeros[i] = "0";
        }
        return string(zeros);
    }

    /// @dev Format an ETH value with the appropriate decimal point
    /// @param value The ETH value to format (after division by 1e14)
    function _formatEthValue(
        uint256 value
    ) internal pure returns (string memory) {
        string memory valueStr = vm.toString(value);
        uint256 len = bytes(valueStr).length;

        if (len > 4) {
            return
                string.concat(
                    slice(valueStr, 0, len - 4),
                    ".",
                    slice(valueStr, len - 4, len)
                );
        } else {
            // Handle small values (less than 1 ETH)
            return string.concat("0.", _padZeros(4 - len), valueStr);
        }
    }

    /// @dev Format a USD value with the appropriate decimal point
    /// @param value The USD value to format (after division by 1e16)
    function _formatUsdValue(
        uint256 value
    ) internal pure returns (string memory) {
        string memory valueStr = vm.toString(value);
        uint256 len = bytes(valueStr).length;

        if (len > 2) {
            return
                string.concat(
                    slice(valueStr, 0, len - 2),
                    ".",
                    slice(valueStr, len - 2, len)
                );
        } else {
            // Handle small values (less than 1 USD)
            return string.concat("0.", _padZeros(2 - len), valueStr);
        }
    }

    /// @dev Helper function to display current collateral and debt balances for a position
    /// @param position_ The address of the position to analyze
    function _displayCurrentBalances(address position_) internal view {
        // Get position assets (collateral) and debt pools
        address[] memory positionAssets = IPosition(position_)
            .getPositionAssets();
        uint256[] memory debtPools = IPosition(position_).getDebtPools();

        // Display current collateral balances
        console2.log("Current collateral balances:");
        for (uint256 i = 0; i < positionAssets.length; ++i) {
            uint256 balance = IERC20(positionAssets[i]).balanceOf(position_);
            string memory balanceStr = _formatEthValue(balance / 1e14);
            string memory symbol = IERC20(positionAssets[i]).symbol();
            console2.log(string.concat(symbol, ": ", balanceStr));
        }

        // Display current debt balances
        console2.log("Current debt balances:");
        for (uint256 i = 0; i < debtPools.length; ++i) {
            address asset = pool.getPoolAssetFor(debtPools[i]);
            uint256 balance = pool.getBorrowsOf(debtPools[i], position_);
            string memory balanceStr = _formatEthValue(balance / 1e14);
            // Use symbol instead of address
            string memory symbol = IERC20(asset).symbol();
            console2.log(string.concat(symbol, ": ", balanceStr));
        }
    }

    /// @dev Helper function to display historical collateral and debt balances for a position
    /// @param position_ The address of the position to analyze
    function _displayHistoricalBalances(address position_) internal view {
        // Get position assets and debt pools at this historical block
        address[] memory positionAssets = IPosition(position_)
            .getPositionAssets();
        uint256[] memory debtPools = IPosition(position_).getDebtPools();

        // Display historical collateral balances
        console2.log("  Collateral balances:");
        for (uint256 i = 0; i < positionAssets.length; ++i) {
            address asset = positionAssets[i];
            uint256 balance = IERC20(asset).balanceOf(position_);
            // Use symbol instead of address
            string memory symbol = IERC20(asset).symbol();
            console2.log(
                string.concat(
                    "  ",
                    symbol,
                    ": ",
                    _formatEthValue(balance / 1e14)
                )
            );
        }

        // Display historical debt balances
        console2.log("  Debt balances:");
        for (uint256 i = 0; i < debtPools.length; ++i) {
            address asset = pool.getPoolAssetFor(debtPools[i]);
            uint256 balance = pool.getBorrowsOf(debtPools[i], position_);
            // Use symbol instead of address
            string memory symbol = IERC20(asset).symbol();
            console2.log(
                string.concat(
                    "  ",
                    symbol,
                    ": ",
                    _formatEthValue(balance / 1e14)
                )
            );
        }
    }

    /// @dev Helper function to display NAV change in collateral asset terms
    /// @param oldNav The oldest NAV value in ETH
    /// @param newNav The newest NAV value in ETH
    /// @param oldestBlockNumber The oldest block number to get historical price
    function _displayNavChangeInCollateral(
        uint256 oldNav,
        uint256 newNav,
        uint256 oldestBlockNumber
    ) internal {
        try position.getPositionAssets() returns (
            address[] memory positionAssets
        ) {
            if (positionAssets.length == 0) {
                console2.log("No collateral assets found in position");
                return;
            }

            address collateralAsset = positionAssets[0]; // Assume first position asset is the collateral (wstHype)

            // Store current fork to return to it later
            uint256 currentForkId = vm.activeFork();
            string
                memory archiveRpcUrl = "https://rpc.hyperlend.finance/archive";

            // Use the oldest block number that was passed as a parameter
            // This is the same block number used for the oldest NAV calculation

            // Create a fork at the oldest block to get the collateral price at that time
            vm.selectFork(vm.createFork(archiveRpcUrl, oldestBlockNumber));

            // Re-initialize contracts in historical context
            IPosition histPosition = IPosition(address(position));
            IRiskEngine histRiskEngine = IRiskEngine(
                histPosition.RISK_ENGINE()
            );

            // Get collateral value in ETH at the oldest block
            uint256 oldEthValue;
            try histRiskEngine.oracleFor(collateralAsset) returns (
                address oracle
            ) {
                try
                    IOracle(oracle).getValueInEth(collateralAsset, 1e18)
                returns (uint256 value) {
                    oldEthValue = value;
                } catch {
                    oldEthValue = 0;
                }
            } catch {
                oldEthValue = 0;
            }

            // Return to current fork
            vm.selectFork(currentForkId);

            // Get current collateral value in ETH
            uint256 newEthValue = _getValueInEth(collateralAsset, 1e18);

            if (oldEthValue == 0 || newEthValue == 0) {
                console2.log(
                    "Error getting collateral price for one or both time periods"
                );
                return; // Avoid division by zero
            }

            _displayCollateralNavChange(
                collateralAsset,
                oldNav,
                newNav,
                oldEthValue,
                newEthValue
            );
        } catch {
            console2.log(
                "Error accessing position assets, skipping collateral NAV calculation"
            );
        }
    }

    /// @dev Helper function to reduce stack usage when displaying NAV in collateral terms
    function _displayCollateralNavChange(
        address collateralAsset,
        uint256 oldNav,
        uint256 newNav,
        uint256 oldEthValue,
        uint256 newEthValue
    ) internal pure {
        collateralAsset;
        //string memory symbol = IERC20(collateralAsset).symbol();
        string memory symbol = "wstHype"; // Hardcoded symbol for wstHype

        // Calculate collateral per ETH for both time periods
        uint256 oldCollateralPerEth = 1e36 / oldEthValue;
        uint256 newCollateralPerEth = 1e36 / newEthValue;

        // Calculate values in collateral terms - use corresponding ETH values for each period
        uint256 oldNavCollateral = (oldNav * oldCollateralPerEth) / 1e18;
        uint256 newNavCollateral = (newNav * newCollateralPerEth) / 1e18;

        // Log part 1 - values
        console2.log(
            string.concat(
                "Total NAV change in ",
                symbol,
                ": ",
                _formatEthValue(oldNavCollateral / 1e14),
                " ",
                symbol,
                " -> ",
                _formatEthValue(newNavCollateral / 1e14),
                " ",
                symbol
            )
        );

        // Calculate percentage change
        int256 collateralDiff = int256(newNavCollateral) -
            int256(oldNavCollateral);
        int256 percentChange = oldNavCollateral > 0
            ? (collateralDiff * 10_000) / int256(oldNavCollateral)
            : int256(0);

        // Format percentage part first to reduce stack usage
        string memory percentStr = string.concat(
            percentChange >= 0 ? "+" : "",
            vm.toString(percentChange / 100),
            ".",
            vm.toString(
                percentChange < 0 ? -percentChange % 100 : percentChange % 100
            ),
            "%"
        );

        // Log part 2 - percentage change (with fewer variables on stack)
        console2.log(
            string.concat("Percentage change: ", percentStr, " (", symbol, ")")
        );
    }

    /// @dev Helper function to display historical NAV line to reduce stack usage in main function
    /// @param blockNumber The block number for this historical point
    /// @param navValue The NAV value in ETH
    /// @param percentChange The percentage change from the previous day
    function _displayHistoricalNavLine(
        uint256 blockNumber,
        uint256 navValue,
        int256 percentChange
    ) internal view {
        console2.log(
            string.concat(
                vm.toString(blockNumber),
                " | ",
                _formatEthValue(navValue / 1e14),
                " ETH, ",
                _formatUsdValue(ethToUsd(navValue) / 1e16),
                " USD | ",
                percentChange > 0 ? "+" : (percentChange == 0 ? "+" : ""),
                vm.toString(percentChange / 100),
                ".",
                vm.toString(
                    percentChange < 0
                        ? -percentChange % 100
                        : percentChange % 100
                ),
                "%"
            )
        );
    }

    /// @dev Helper function to display total NAV change to reduce stack usage in main function
    /// @param oldNav The oldest NAV value in ETH
    /// @param newNav The newest NAV value in ETH
    /// @param oldestBlockNumber The oldest block number
    function _displayTotalNavChange(
        uint256 oldNav,
        uint256 newNav,
        uint256 oldestBlockNumber
    ) internal {
        // Calculate percentage change in ETH terms
        int256 totalPercentChangeEth = int256(
            ((int256(newNav) - int256(oldNav)) * 10_000) / int256(oldNav)
        );

        // Format the NAV values for display
        string memory oldNavStr = _formatEthValue(oldNav / 1e14);
        string memory newNavStr = _formatEthValue(newNav / 1e14);

        // Display ETH NAV change - days count is hardcoded to avoid stack issues
        console2.log(
            string.concat(
                "\nTotal NAV change: ",
                oldNavStr,
                " ETH -> ",
                newNavStr,
                " ETH: ",
                totalPercentChangeEth >= 0 ? "+" : "",
                vm.toString(totalPercentChangeEth / 100),
                ".",
                vm.toString(
                    totalPercentChangeEth < 0
                        ? -totalPercentChangeEth % 100
                        : totalPercentChangeEth % 100
                ),
                "% (ETH)"
            )
        );

        // Calculate change in terms of wstHype (collateral asset)
        _displayNavChangeInCollateral(oldNav, newNav, oldestBlockNumber);
    }

    /// @dev Find the block where a contract was first created using binary search
    /// @param contractAddress The address of the contract to check
    /// @param rpcUrl The RPC URL to use for the forks
    /// @param startBlock The lower bound for the search
    /// @param endBlock The upper bound for the search
    function findContractCreationBlock(
        address contractAddress,
        string memory rpcUrl,
        uint256 startBlock,
        uint256 endBlock
    ) internal returns (uint256) {
        // Binary search to find approximate contract creation block
        uint256 contractCreationBlock;
        uint256 low = startBlock;
        uint256 high = endBlock;

        vm.selectFork(vm.createFork(rpcUrl)); // Start with a fresh fork

        while (low <= high) {
            uint256 mid = (low + high) / 2;
            uint256 forkId = vm.createFork(rpcUrl, mid);
            vm.selectFork(forkId);

            // Check if the contract has code at this block
            bool exists = contractAddress.code.length > 0;

            if (exists) {
                // Contract exists at this block, check earlier
                contractCreationBlock = mid;
                high = mid - 1;
            } else {
                // Contract doesn't exist yet, check later blocks
                low = mid + 1;
            }
        }

        return contractCreationBlock;
    }

    /// @dev Find the closest block to a given timestamp using binary search
    /// @param rpcUrl The RPC URL to use for the forks
    /// @param targetTimestamp The timestamp to look for
    function findBlockNumberByTimestamp(
        string memory rpcUrl,
        uint256 targetTimestamp
    ) internal returns (uint256) {
        // Use binary search to find the closest block to the target timestamp
        uint256 low = 0;
        uint256 high = block.number;
        uint256 mid;
        uint256 midTimestamp;

        while (low <= high) {
            mid = (low + high) / 2;

            // Fork to the mid block and get its timestamp
            vm.selectFork(vm.createFork(rpcUrl, mid));
            midTimestamp = block.timestamp;

            // Check if we're within an acceptable range (1 hour)
            if (
                midTimestamp > targetTimestamp &&
                midTimestamp - targetTimestamp < 3600
            ) {
                return mid;
            }
            if (
                targetTimestamp > midTimestamp &&
                targetTimestamp - midTimestamp < 3600
            ) {
                return mid;
            }

            // Adjust search range
            if (midTimestamp < targetTimestamp) {
                low = mid + 1;
            } else {
                high = mid - 1;
            }
        }

        return mid; // Return closest block found
    }

    /// @dev Helper function to calculate the NAV at a specific historical block
    /// @param position_ The address of the position to analyze
    /// @param rpcUrl The RPC URL to use for the fork
    /// @param blockNumber The block number to get the NAV for
    /// @return nav The NAV value at the specified block
    function _getHistoricalNavAtBlock(
        address position_,
        string memory rpcUrl,
        uint256 blockNumber
    ) internal returns (uint256 nav) {
        // Create a fork at the historical block number
        vm.selectFork(vm.createFork(rpcUrl, blockNumber));

        // Re-initialize contracts in the forked context
        IPosition histPosition = IPosition(position_);
        IRiskEngine histRiskEngine = IRiskEngine(histPosition.RISK_ENGINE());

        // Calculate NAV at this historical point
        try histRiskEngine.getRiskData(position_) returns (
            uint256 assetValue,
            uint256 debtValue,
            uint256
        ) {
            nav = assetValue > debtValue ? assetValue - debtValue : 0;
        } catch {
            console2.log(
                "%d | Error calculating NAV at this block",
                blockNumber
            );
            nav = 0;
        }

        // Reset back to a fresh archive fork to avoid any state interference
        vm.selectFork(vm.createFork(rpcUrl));
        return nav;
    }

    /// @dev Calculate current NAV and historical NAV values at 24-hour intervals
    /// @param position_ The address of the position to analyze
    /// @param daysBack Number of days to look back in history (default: 7)
    function getHistoricNav(address position_, uint256 daysBack) public {
        if (daysBack == 0) daysBack = 7; // Default to 7 days if not specified

        _run();

        // Set up position contracts for current state
        position = IPosition(position_);
        pool = IPool(position.POOL());
        riskEngine = IRiskEngine(position.RISK_ENGINE());

        console2.log("Position Nav History:", position_);

        // Store the current block number for reference
        uint256 currentBlock = block.number;
        console2.log("Current block:", currentBlock);

        // Calculate and display the current NAV first
        (uint256 currentAssetValue, uint256 currentDebtValue, ) = riskEngine
            .getRiskData(position_);
        uint256 currentNav = currentAssetValue > currentDebtValue
            ? currentAssetValue - currentDebtValue
            : 0;

        console2.log("Current NAV:");
        console2.log(
            "%4e ETH, %2e USD",
            currentNav / 1e14,
            ethToUsd(currentNav) / 1e16
        );

        // Create arrays to store historical data
        uint256[] memory blockNumbers = new uint256[](daysBack + 1); // +1 to include current day
        uint256[] memory navValues = new uint256[](daysBack + 1); // +1 to include current day

        // Calculate historical NAVs using archival node
        string memory archiveRpcUrl = "https://hl-archive-node.xyz";

        console2.log("\nHistorical NAV values:");
        console2.log("Block Number | NAV (ETH) | NAV (USD) | % Change");
        console2.log("------------------------------------------------");

        // Get current timestamp
        uint256 currentTime = block.timestamp;
        uint256 secondsPerDay = 24 * 60 * 60; // 86400 seconds in a day

        // Calculate timestamps and find corresponding blocks
        uint256[] memory targetTimestamps = new uint256[](daysBack + 1);

        // First, define our target timestamps (exactly X days apart)
        for (uint256 i = 0; i <= daysBack; i++) {
            if (i == 0) {
                // Oldest date (daysBack days ago)
                targetTimestamps[i] = currentTime - (daysBack * secondsPerDay);
            } else if (i == daysBack) {
                // Current date
                targetTimestamps[i] = currentTime;
            } else {
                // Intermediate dates
                targetTimestamps[i] =
                    currentTime -
                    ((daysBack - i) * secondsPerDay);
            }
        }

        // Next, find the blocks closest to these timestamps
        for (uint256 i = 0; i <= daysBack; i++) {
            if (i == daysBack) {
                // For current time, just use current block
                blockNumbers[i] = currentBlock;
                continue;
            }

            // Find block number closest to our target timestamp using binary search
            blockNumbers[i] = findBlockNumberByTimestamp(
                archiveRpcUrl,
                targetTimestamps[i]
            );
        }

        // Find when the position contract was actually created using a helper function
        uint256 contractCreationBlock = findContractCreationBlock(
            position_,
            archiveRpcUrl,
            blockNumbers[0],
            currentBlock
        );

        console2.log(
            "Position contract was created at block:",
            contractCreationBlock
        );

        // For contracts created recently, space out blocks evenly from creation to current
        bool useCreationBasedBlocks = false;

        // Check if the oldest requested block is close to creation block (within 1 day)
        if (
            blockNumbers[0] < contractCreationBlock ||
            (contractCreationBlock > 0 &&
                (blockNumbers[0] - contractCreationBlock) < 7200)
        ) {
            useCreationBasedBlocks = true;
        }

        if (useCreationBasedBlocks && contractCreationBlock > 0) {
            console2.log(
                "Contract is recently created. Using evenly spaced blocks since creation."
            );

            // Calculate blocks evenly spaced from creation to current
            uint256 totalBlockSpan = currentBlock - contractCreationBlock;
            uint256 blockStep = totalBlockSpan / daysBack;

            if (blockStep == 0) blockStep = 1; // Ensure minimum step of 1 block

            for (uint256 i = 0; i <= daysBack; i++) {
                if (i == daysBack) {
                    blockNumbers[i] = currentBlock; // Keep current block at the end
                } else {
                    // Distribute blocks evenly from creation to current
                    blockNumbers[i] = contractCreationBlock + (i * blockStep);
                }
            }
        } else {
            // Standard behavior for older contracts - just ensure blocks aren't before creation
            for (uint256 i = 0; i <= daysBack; i++) {
                if (blockNumbers[i] < contractCreationBlock) {
                    blockNumbers[i] = contractCreationBlock;
                }
            }
        }

        // Store the values in chronological order (oldest first)
        for (uint256 i = 0; i <= daysBack; i++) {
            if (i == daysBack) {
                // Current NAV
                navValues[i] = currentNav;
                continue;
            }

            // Calculate NAV for this historical block using helper function
            navValues[i] = _getHistoricalNavAtBlock(
                position_,
                archiveRpcUrl,
                blockNumbers[i]
            );

            // Calculate percentage change from previous day
            int256 percentChange = 0;
            if (i > 0 && navValues[i - 1] > 0) {
                percentChange = int256(
                    ((int256(navValues[i]) - int256(navValues[i - 1])) *
                        10_000) / int256(navValues[i - 1])
                );
            }

            // Display NAV with percentage change
            _displayHistoricalNavLine(
                blockNumbers[i],
                navValues[i],
                percentChange
            );
        }

        // Show overall change during the period
        if (navValues[daysBack] > 0 && navValues[0] > 0) {
            // Display total NAV change using helper function to reduce stack usage
            _displayTotalNavChange(
                navValues[0],
                navValues[daysBack],
                blockNumbers[0]
            );
        }
    }
}
