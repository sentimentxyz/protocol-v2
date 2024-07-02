// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                                Pool
//////////////////////////////////////////////////////////////*/

// types
import { Registry } from "./Registry.sol";
import { IRateModel } from "./interfaces/IRateModel.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

// contracts
import { ERC6909 } from "./lib/ERC6909.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title Pool
/// @notice Singleton pool for all pools that superpools lend to and positions borrow from
contract Pool is OwnableUpgradeable, ERC6909 {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice Initial interest fee for pools
    uint128 public constant DEFAULT_INTEREST_FEE = 0;
    /// @notice Initial origination fee for pools
    uint128 public constant DEFAULT_ORIGINATION_FEE = 0;
    /// @notice Timelock delay for pool rate model modification
    uint256 public constant TIMELOCK_DURATION = 24 * 60 * 60; // 24 hours
    /// @notice Registry key hash for the Sentiment position manager
    /// @dev keccak(SENTIMENT_POSITION_MANAGER_KEY)
    bytes32 public constant SENTIMENT_POSITION_MANAGER_KEY =
        0xd4927490fbcbcafca716cca8e8c8b7d19cda785679d224b14f15ce2a9a93e148;

    /// @notice Sentiment registry
    address public registry;
    /// @notice Sentiment fee receiver
    address public feeRecipient;
    /// @notice Sentiment position manager
    address public positionManager;

    /// @notice Fetch the owner for a given pool id
    mapping(uint256 poolId => address poolOwner) public ownerOf;
    /// @notice Fetch debt owed by a given position for a particular pool, denominated in borrow shares
    mapping(uint256 poolId => mapping(address position => uint256 borrowShares)) public borrowSharesOf;

    /// @title Uint128Pair
    /// @notice Store a value in terms of both notional assets and shares using a pair of Uint128s
    struct Uint128Pair {
        uint128 assets;
        uint128 shares;
    }

    /// @title PoolData
    /// @notice Pool config and state container
    struct PoolData {
        address asset;
        address rateModel;
        uint128 poolCap;
        uint128 lastUpdated;
        uint128 interestFee;
        uint128 originationFee;
        bool isPaused;
        Uint128Pair totalAssets;
        Uint128Pair totalBorrows;
    }

    /// @notice Fetch pool config and state for a given pool id
    mapping(uint256 poolId => PoolData data) public poolDataFor;

    /// @title RateModelUpdate
    /// @notice Utility struct to store pending pool rate model updates
    struct RateModelUpdate {
        address rateModel;
        uint256 validAfter;
    }

    /// @notice Fetch pending rate model updates for a given pool id
    mapping(uint256 poolId => RateModelUpdate rateModelUpdate) public rateModelUpdateFor;

    /// @notice Registry address was set
    event RegistrySet(address registry);
    /// @notice Paused state of a pool was toggled
    event PoolPauseToggled(uint256 poolId, bool paused);
    /// @notice Asset cap for a pool was set
    event PoolCapSet(uint256 indexed poolId, uint128 poolCap);
    /// @notice Owner for a pool was set
    event PoolOwnerSet(uint256 indexed poolId, address owner);
    /// @notice Rate model for a pool was updated
    event RateModelUpdated(uint256 indexed poolId, address rateModel);
    /// @notice Interest fee for a pool was updated
    event InterestFeeSet(uint256 indexed poolId, uint128 interestFee);
    /// @notice Origination fee for a pool was updated
    event OriginationFeeSet(uint256 indexed poolId, uint128 originationFee);
    /// @notice Pending rate model update for a pool was rejected
    event RateModelUpdateRejected(uint256 indexed poolId, address rateModel);
    /// @notice Rate model update for a pool was proposed
    event RateModelUpdateRequested(uint256 indexed poolId, address rateModel);
    /// @notice New pool was initialized
    event PoolInitialized(uint256 indexed poolId, address indexed owner, address indexed asset);
    /// @notice Assets were deposited to a pool
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    /// @notice Debt was repaid from a position to a pool
    event Repay(address indexed position, uint256 indexed poolId, address indexed asset, uint256 amount);
    /// @notice Assets were borrowed from a position to a pool
    event Borrow(address indexed position, uint256 indexed poolId, address indexed asset, uint256 amount);
    /// @notice Assets were withdrawn from a pool
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /// @notice Given fee value is greater than 100%
    error Pool_FeeTooHigh();
    /// @notice Zero address cannot be the pool owner
    error Pool_ZeroAddressOwner();
    /// @notice Pool is paused
    error Pool_PoolPaused(uint256 poolId);
    /// @notice Pool deposits exceed asset cap
    error Pool_PoolCapExceeded(uint256 poolId);
    /// @notice No pending rate model update for the pool
    error Pool_NoRateModelUpdate(uint256 poolId);
    /// @notice Attempt to initialize an already existing pool
    error Pool_PoolAlreadyInitialized(uint256 poolId);
    /// @notice Attempt to redeem zero shares worth of assets from the pool
    error Pool_ZeroShareRedeem(uint256 poolId, uint256 assets);
    /// @notice Attempt to repay zero shares worth of assets to the pool
    error Pool_ZeroSharesRepay(uint256 poolId, uint256 amt);
    /// @notice Attempt to borrow zero shares worth of assets from the pool
    error Pool_ZeroSharesBorrow(uint256 poolId, uint256 amt);
    /// @notice Attempt to deposit zero shares worth of assets to the pool
    error Pool_ZeroSharesDeposit(uint256 poolId, uint256 amt);
    /// @notice Function access restricted only to the pool owner
    error Pool_OnlyPoolOwner(uint256 poolId, address sender);
    /// @notice Function access restricted only to Sentiment Position Manager
    error Pool_OnlyPositionManager(uint256 poolId, address sender);
    /// @notice Insufficient pool liquidity to service borrow
    error Pool_InsufficientBorrowLiquidity(uint256 poolId, uint256 assetsInPool, uint256 assets);
    /// @notice Insufficient pool liquidity to service withdrawal
    error Pool_InsufficientWithdrawLiquidity(uint256 poolId, uint256 assetsInPool, uint256 assets);
    /// @notice Rate model timelock delay has not been completed
    error Pool_TimelockPending(uint256 poolId, uint256 currentTimestamp, uint256 validAfter);

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer for TransparentUpgradeableProxy
    /// @param owner_ Pool owner
    /// @param registry_ Sentiment Registry
    /// @param feeRecipient_ Sentiment fee receiver
    function initialize(address owner_, address registry_, address feeRecipient_) public initializer {
        OwnableUpgradeable.__Ownable_init();
        _transferOwnership(owner_);

        registry = registry_;
        feeRecipient = feeRecipient_;
        updateFromRegistry();
    }

    /// @notice Fetch and update module addreses from the registry
    function updateFromRegistry() public {
        positionManager = Registry(registry).addressFor(SENTIMENT_POSITION_MANAGER_KEY);
    }

    /// @notice Fetch amount of liquid assets currently held in a given pool
    function getLiquidityOf(uint256 poolId) public view returns (uint256) {
        PoolData storage pool = poolDataFor[poolId];
        uint256 pendingInterest = simulateAccrue(pool);
        return pool.totalAssets.assets + pendingInterest - pool.totalBorrows.assets;
    }

    /// @notice Fetch pool asset balance for depositor to a pool
    function getAssetsOf(uint256 poolId, address guy) public view returns (uint256) {
        PoolData storage pool = poolDataFor[poolId];
        uint256 pendingInterest = simulateAccrue(pool);
        Uint128Pair memory totalAssets = pool.totalAssets;
        totalAssets.assets += uint128(pendingInterest);
        return convertToAssets(totalAssets, balanceOf[guy][poolId]);
    }

    /// @notice Fetch debt owed by a position to a given pool
    function getBorrowsOf(uint256 poolId, address position) public view returns (uint256) {
        PoolData storage pool = poolDataFor[poolId];
        uint256 pendingInterest = simulateAccrue(pool);
        Uint128Pair memory totalBorrows = pool.totalBorrows;
        totalBorrows.assets += uint128(pendingInterest);
        return convertToAssets(totalBorrows, borrowSharesOf[poolId][position]);
    }

    /// @notice Fetch the total amount of assets currently deposited in a pool
    function getTotalAssets(uint256 poolId) public view returns (uint256) {
        PoolData storage pool = poolDataFor[poolId];
        uint256 pendingInterest = simulateAccrue(pool);
        return pool.totalAssets.assets + pendingInterest;
    }

    /// @notice Fetch total amount of debt owed to a given pool id
    function getTotalBorrows(uint256 poolId) public view returns (uint256) {
        PoolData storage pool = poolDataFor[poolId];
        uint256 pendingInterest = simulateAccrue(pool);
        return pool.totalBorrows.assets + pendingInterest;
    }

    /// @notice Fetch current rate model for a given pool id
    function getRateModelFor(uint256 poolId) public view returns (address rateModel) {
        return poolDataFor[poolId].rateModel;
    }

    /// @notice Fetch the debt asset address for a given pool
    function getPoolAssetFor(uint256 poolId) public view returns (address) {
        return poolDataFor[poolId].asset;
    }

    /// @notice Fetch equivalent shares amount for given assets
    function convertToShares(Uint128Pair memory pair, uint256 assets) public pure returns (uint256 shares) {
        if (pair.assets == 0) return assets;
        shares = assets.mulDiv(pair.shares, pair.assets);
    }

    /// @notice Fetch equivalent asset amount for given shares
    function convertToAssets(Uint128Pair memory pair, uint256 shares) public pure returns (uint256 assets) {
        if (pair.shares == 0) return shares;
        assets = shares.mulDiv(pair.assets, pair.shares);
    }

    /// @notice Deposit assets to a pool
    /// @param poolId Pool id
    /// @param assets Amount of assets to be deposited
    /// @param receiver Address to deposit assets on behalf of
    /// @return shares Amount of pool deposit shares minted
    function deposit(uint256 poolId, uint256 assets, address receiver) public returns (uint256 shares) {
        PoolData storage pool = poolDataFor[poolId];

        if (pool.isPaused) revert Pool_PoolPaused(poolId);

        // update state to accrue interest since the last time accrue() was called
        accrue(pool, poolId);

        if (pool.totalAssets.assets + assets > pool.poolCap) revert Pool_PoolCapExceeded(poolId);

        shares = convertToShares(pool.totalAssets, assets);
        if (shares == 0) revert Pool_ZeroSharesDeposit(poolId, assets);

        // Need to transfer before minting or ERC777s could reenter.
        IERC20(pool.asset).safeTransferFrom(msg.sender, address(this), assets);

        pool.totalAssets.assets += uint128(assets);
        pool.totalAssets.shares += uint128(shares);

        _mint(receiver, poolId, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Withdraw assets from a pool
    /// @param poolId Pool id
    /// @param assets Amount of assets to be redeemed
    /// @param receiver Address that receives redeemed assets
    /// @param owner Address to redeem on behalf of
    /// @return shares Amount of shares redeemed from the pool
    function withdraw(
        uint256 poolId,
        uint256 assets,
        address receiver,
        address owner
    ) public returns (uint256 shares) {
        PoolData storage pool = poolDataFor[poolId];

        // update state to accrue interest since the last time accrue() was called
        accrue(pool, poolId);

        shares = convertToShares(pool.totalAssets, assets);
        // check for rounding error since convertToShares rounds down
        if (shares == 0) revert Pool_ZeroShareRedeem(poolId, assets);

        if (msg.sender != owner && !isOperator[owner][msg.sender]) {
            uint256 allowed = allowance[owner][msg.sender][poolId];
            if (allowed != type(uint256).max) allowance[owner][msg.sender][poolId] = allowed - shares;
        }

        uint256 assetsInPool = pool.totalAssets.assets - pool.totalBorrows.assets;
        if (assetsInPool < assets) revert Pool_InsufficientWithdrawLiquidity(poolId, assetsInPool, assets);

        pool.totalAssets.assets -= uint128(assets);
        pool.totalAssets.shares -= uint128(shares);

        _burn(owner, poolId, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        IERC20(pool.asset).safeTransfer(receiver, assets);
    }

    /// @notice Accrue interest and fees for a given pool
    function accrue(uint256 id) external {
        PoolData storage pool = poolDataFor[id];
        accrue(pool, id);
    }

    function simulateAccrue(PoolData storage pool) internal view returns (uint256 interestAccrued) {
        return IRateModel(pool.rateModel).getInterestAccrued(
            pool.lastUpdated, pool.totalBorrows.assets, pool.totalAssets.assets
        );
    }

    /// @dev update pool state to accrue interest since the last time accrue() was called
    function accrue(PoolData storage pool, uint256 id) internal {
        uint256 interestAccrued = simulateAccrue(pool);

        if (interestAccrued != 0) {
            // [ROUND] floor fees in favor of pool lenders
            uint256 feeAssets = interestAccrued.mulDiv(pool.interestFee, 1e18);

            // [ROUND] round down in favor of pool lenders
            uint256 feeShares = convertToShares(pool.totalAssets, feeAssets);

            _mint(feeRecipient, id, feeShares);
        }

        // update cached notional borrows to current borrow amount
        pool.totalBorrows.assets += uint128(interestAccrued);
        pool.totalAssets.assets += uint128(interestAccrued);

        // store a timestamp for this accrue() call
        // used to compute the pending interest next time accrue() is called
        pool.lastUpdated = uint128(block.timestamp);
        // store a timestamp for this accrue() call
        // used to compute the pending interest next time accrue() is called
        pool.lastUpdated = uint128(block.timestamp);
    }

    /// @notice Mint borrow shares and send borrowed assets to the borrowing position
    /// @param position the position to mint shares to
    /// @param amt the amount of assets to borrow, denominated in notional asset units
    /// @return borrowShares the amount of shares minted
    function borrow(uint256 poolId, address position, uint256 amt) external returns (uint256 borrowShares) {
        PoolData storage pool = poolDataFor[poolId];

        if (pool.isPaused) revert Pool_PoolPaused(poolId);

        // revert if the caller is not the position manager
        if (msg.sender != positionManager) revert Pool_OnlyPositionManager(poolId, msg.sender);

        // update state to accrue interest since the last time accrue() was called
        accrue(pool, poolId);

        // pools cannot share liquidity among themselves, revert if borrow amt exceeds pool liquidity
        uint256 assetsInPool = pool.totalAssets.assets - pool.totalBorrows.assets;
        if (assetsInPool < amt) revert Pool_InsufficientBorrowLiquidity(poolId, assetsInPool, amt);

        // compute borrow shares equivalant for notional borrow amt
        // [ROUND] round up shares minted, to ensure they capture the borrowed amount
        borrowShares = convertToShares(pool.totalBorrows, amt);

        // revert if borrow amt is too small
        if (borrowShares == 0) revert Pool_ZeroSharesBorrow(poolId, amt);

        // update total pool debt, denominated in notional asset units and shares
        pool.totalBorrows.assets += uint128(amt);
        pool.totalBorrows.shares += uint128(borrowShares);

        // update position debt, denominated in borrow shares
        borrowSharesOf[poolId][position] += borrowShares;

        // compute origination fee amt
        // [ROUND] origination fee is rounded down, in favor of the borrower
        uint256 fee = amt.mulDiv(pool.originationFee, 1e18);

        address asset = pool.asset;
        // send origination fee to owner
        IERC20(asset).safeTransfer(feeRecipient, fee);

        // send borrowed assets to position
        IERC20(asset).safeTransfer(position, amt - fee);

        emit Borrow(position, poolId, asset, amt);
    }

    /// @notice Decrease position debt via repayment of debt and burn borrow shares
    /// @dev Assumes assets have already been sent to the pool
    /// @param position the position for which debt is being repaid
    /// @param amt the notional amount of debt asset repaid
    /// @return remainingShares remaining debt in borrow shares owed by the position
    function repay(uint256 poolId, address position, uint256 amt) external returns (uint256 remainingShares) {
        PoolData storage pool = poolDataFor[poolId];

        // the only way to call repay() is through the position manager
        // PositionManager.repay() MUST transfer the assets to be repaid before calling Pool.repay()
        // this function assumes the transfer of assets was completed successfully

        // there is an implicit assumption that assets were transferred in the same txn lest
        // the call to Pool.repay() is not frontrun allowing debt repayment for another position

        // revert if the caller is not the position manager
        if (msg.sender != positionManager) revert Pool_OnlyPositionManager(poolId, msg.sender);

        // update state to accrue interest since the last time accrue() was called
        accrue(pool, poolId);

        // compute borrow shares equivalent to notional asset amt
        // [ROUND] burn fewer borrow shares, to ensure excess debt isn't pushed to others
        uint256 borrowShares = convertToShares(pool.totalBorrows, amt);

        // revert if repaid amt is too small
        if (borrowShares == 0) revert Pool_ZeroSharesRepay(poolId, amt);

        // update total pool debt, denominated in notional asset units, and shares
        pool.totalBorrows.assets -= uint128(amt);
        pool.totalBorrows.shares -= uint128(borrowShares);

        emit Repay(position, poolId, pool.asset, amt);

        // return the remaining position debt, denominated in borrow shares
        return (borrowSharesOf[poolId][position] -= borrowShares);
    }

    /// @notice Initialize a new pool
    /// @param owner Pool owner
    /// @param asset Pool debt asset
    /// @param rateModel Pool interest rate model
    /// @param poolCap Pool asset cap
    /// @return poolId Pool id for initialized pool
    function initializePool(
        address owner,
        address asset,
        address rateModel,
        uint128 poolCap
    ) external returns (uint256 poolId) {
        if (owner == address(0)) revert Pool_ZeroAddressOwner();
        poolId = uint256(keccak256(abi.encodePacked(owner, asset, rateModel)));

        if (ownerOf[poolId] != address(0)) revert Pool_PoolAlreadyInitialized(poolId);
        ownerOf[poolId] = owner;

        PoolData memory poolData = PoolData({
            asset: asset,
            rateModel: rateModel,
            poolCap: poolCap,
            lastUpdated: uint128(block.timestamp),
            interestFee: DEFAULT_INTEREST_FEE,
            originationFee: DEFAULT_ORIGINATION_FEE,
            isPaused: false,
            totalAssets: Uint128Pair(0, 0),
            totalBorrows: Uint128Pair(0, 0)
        });

        poolDataFor[poolId] = poolData;

        emit PoolInitialized(poolId, owner, asset);
        emit RateModelUpdated(poolId, rateModel);
        emit PoolCapSet(poolId, poolCap);
    }

    /// @notice Toggle paused state for a pool to restrict deposit and borrows
    function togglePause(uint256 poolId) external {
        if (msg.sender != ownerOf[poolId]) revert Pool_OnlyPoolOwner(poolId, msg.sender);
        PoolData storage pool = poolDataFor[poolId];
        pool.isPaused = !pool.isPaused;
        emit PoolPauseToggled(poolId, pool.isPaused);
    }

    /// @notice Update pool asset cap to restrict total amount of assets deposited
    function setPoolCap(uint256 poolId, uint128 poolCap) external {
        if (msg.sender != ownerOf[poolId]) revert Pool_OnlyPoolOwner(poolId, msg.sender);
        poolDataFor[poolId].poolCap = poolCap;
        emit PoolCapSet(poolId, poolCap);
    }

    /// @notice Propose a interest rate model update for a pool
    function requestRateModelUpdate(uint256 poolId, address rateModel) external {
        if (msg.sender != ownerOf[poolId]) revert Pool_OnlyPoolOwner(poolId, msg.sender);
        RateModelUpdate memory rateModelUpdate =
            RateModelUpdate({ rateModel: rateModel, validAfter: block.timestamp + TIMELOCK_DURATION });

        rateModelUpdateFor[poolId] = rateModelUpdate;

        emit RateModelUpdateRequested(poolId, rateModel);
    }

    /// @notice Apply a pending interest rate model change for a pool
    function acceptRateModelUpdate(uint256 poolId) external {
        if (msg.sender != ownerOf[poolId]) revert Pool_OnlyPoolOwner(poolId, msg.sender);
        RateModelUpdate memory rateModelUpdate = rateModelUpdateFor[poolId];
        if (rateModelUpdate.validAfter == 0) revert Pool_NoRateModelUpdate(poolId);
        if (block.timestamp < rateModelUpdate.validAfter) {
            revert Pool_TimelockPending(poolId, block.timestamp, rateModelUpdate.validAfter);
        }
        poolDataFor[poolId].rateModel = rateModelUpdate.rateModel;
        delete rateModelUpdateFor[poolId];
        emit RateModelUpdated(poolId, rateModelUpdate.rateModel);
    }

    /// @notice Reject pending interest rate model update
    function rejectRateModelUpdate(uint256 poolId) external {
        if (msg.sender != ownerOf[poolId]) revert Pool_OnlyPoolOwner(poolId, msg.sender);
        emit RateModelUpdateRejected(poolId, rateModelUpdateFor[poolId].rateModel);
        delete rateModelUpdateFor[poolId];
    }

    /// @notice Set protocol registry address
    /// @param _registry Registry address
    function setRegistry(address _registry) external onlyOwner {
        registry = _registry;
        emit RegistrySet(_registry);
    }

    /// @notice Set interest fee for given pool
    /// @param poolId Pool id
    /// @param interestFee New interest fee
    function setInterestFee(uint256 poolId, uint128 interestFee) external onlyOwner {
        if (interestFee > 1e18) revert Pool_FeeTooHigh();
        poolDataFor[poolId].interestFee = interestFee;
        emit InterestFeeSet(poolId, interestFee);
    }

    /// @notice Set origination fee for given pool
    /// @param poolId Pool id
    /// @param originationFee New origination fee
    function setOriginationFee(uint256 poolId, uint128 originationFee) external onlyOwner {
        if (originationFee > 1e18) revert Pool_FeeTooHigh();
        poolDataFor[poolId].originationFee = originationFee;
        emit OriginationFeeSet(poolId, originationFee);
    }
}
