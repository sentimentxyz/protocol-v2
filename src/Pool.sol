// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {Registry} from "./Registry.sol";
import {IRateModel} from "./interfaces/IRateModel.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
// libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// contracts
import {ERC6909} from "./lib/ERC6909.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Pool is OwnableUpgradeable, ERC6909 {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               Structs
    //////////////////////////////////////////////////////////////*/

    struct RateModelUpdate {
        address rateModel;
        uint256 validAfter;
    }

    struct Uint128Pair {
        uint128 assets;
        uint128 shares;
    }

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

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    uint256 public constant TIMELOCK_DURATION = 24 * 60 * 60; // 24 hours

    // keccak(SENTIMENT_POSITION_MANAGER_KEY)
    bytes32 public constant SENTIMENT_POSITION_MANAGER_KEY =
        0xd4927490fbcbcafca716cca8e8c8b7d19cda785679d224b14f15ce2a9a93e148;

    Registry public REGISTRY;

    address public feeRecipient; // address that receives protocol fees
    address public positionManager;

    mapping(uint256 poolId => address poolOwner) public ownerOf;
    mapping(uint256 poolId => PoolData data) public poolDataFor;
    mapping(uint256 poolId => RateModelUpdate rateModelUpdate) public rateModelUpdateFor;
    mapping(uint256 poolId => mapping(address position => uint256 borrowShares)) public borrowSharesOf;

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event PoolPauseToggled(uint256 poolId, bool paused);
    event PoolCapSet(uint256 indexed poolId, uint128 poolCap);
    event PoolOwnerSet(uint256 indexed poolId, address owner);
    event RateModelUpdated(uint256 indexed poolId, address rateModel);
    event InterestFeeSet(uint256 indexed poolId, uint128 interestFee);
    event OriginationFeeSet(uint256 indexed poolId, uint128 originationFee);
    event RateModelUpdateRejected(uint256 indexed poolId, address rateModel);
    event RateModelUpdateRequested(uint256 indexed poolId, address rateModel);
    event Repay(address indexed position, address indexed asset, uint256 amount);
    event Borrow(address indexed position, address indexed asset, uint256 amount);
    event PoolInitialized(uint256 indexed poolId, address indexed owner, address indexed asset);
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /*//////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/

    error Pool_AlreadyInitialized();
    error Pool_PoolPaused(uint256 poolId);
    error Pool_PoolCapExceeded(uint256 poolId);
    error Pool_NoRateModelUpdate(uint256 poolId);
    error Pool_InsufficientLiquidity(uint256 poolId);
    error Pool_PoolAlreadyInitialized(uint256 poolId);
    error Pool_ZeroAssetRedeem(uint256 poolId, uint256 shares);
    error Pool_ZeroSharesRepay(uint256 poolId, uint256 amt);
    error Pool_ZeroSharesBorrow(uint256 poolId, uint256 amt);
    error Pool_ZeroSharesDeposit(uint256 poolId, uint256 amt);
    error Pool_OnlyPoolOwner(uint256 poolId, address sender);
    error Pool_OnlyPositionManager(uint256 poolId, address sender);
    error Pool_TimelockPending(uint256 poolId, uint256 currentTimestamp, uint256 validAfter);

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address registry_, address feeRecipient_) public initializer {
        OwnableUpgradeable.__Ownable_init(msg.sender);

        feeRecipient = feeRecipient_;
        REGISTRY = Registry(registry_);
    }

    function updateFromRegistry() external {
        positionManager = REGISTRY.addressFor(SENTIMENT_POSITION_MANAGER_KEY);
    }

    /*//////////////////////////////////////////////////////////////
                        Public View Functions
    //////////////////////////////////////////////////////////////*/

    function getAssetsOf(uint256 poolId, address guy) public view returns (uint256 assets) {
        Uint128Pair memory totalAssets = poolDataFor[poolId].totalAssets;
        assets = convertToAssets(totalAssets, balanceOf[guy][poolId]);
    }

    function getBorrowsOf(uint256 poolId, address position) public view returns (uint256 borrows) {
        Uint128Pair memory totalBorrows = poolDataFor[poolId].totalBorrows;
        borrows = convertToAssets(totalBorrows, borrowSharesOf[poolId][position]);
    }

    function getTotalBorrows(uint256 poolId) public view returns (uint256) {
        return poolDataFor[poolId].totalBorrows.assets;
    }

    function getRateModelFor(uint256 poolId) public view returns (address) {
        return poolDataFor[poolId].rateModel;
    }

    function getPoolAssetFor(uint256 poolId) public view returns (address) {
        return poolDataFor[poolId].asset;
    }

    function convertToShares(Uint128Pair memory pair, uint256 assets) public pure returns (uint256 shares) {
        if (pair.assets == 0) return assets;
        shares = assets.mulDiv(pair.shares, pair.assets);
    }

    function convertToAssets(Uint128Pair memory pair, uint256 shares) public pure returns (uint256 assets) {
        if (pair.shares == 0) return shares;
        assets = shares.mulDiv(pair.assets, pair.shares);
    }

    /*//////////////////////////////////////////////////////////////
                          Lending Functionality
    //////////////////////////////////////////////////////////////*/

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

    function redeem(uint256 poolId, uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        PoolData storage pool = poolDataFor[poolId];

        // update state to accrue interest since the last time accrue() was called
        accrue(pool, poolId);

        if (msg.sender != owner && !isOperator[owner][msg.sender]) {
            uint256 allowed = allowance[owner][msg.sender][poolId];
            if (allowed != type(uint256).max) allowance[owner][msg.sender][poolId] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        assets = convertToAssets(pool.totalAssets, shares);
        if (assets == 0) revert Pool_ZeroAssetRedeem(poolId, shares);
        if (pool.totalAssets.assets - assets >= pool.totalBorrows.assets) revert Pool_InsufficientLiquidity(poolId);

        pool.totalAssets.assets -= uint128(assets);
        pool.totalAssets.shares -= uint128(shares);

        _burn(owner, poolId, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        IERC20(pool.asset).safeTransfer(receiver, assets);
    }

    /*//////////////////////////////////////////////////////////////
                             Pool Actions
    //////////////////////////////////////////////////////////////*/

    function accrue(uint256 id) external {
        PoolData storage pool = poolDataFor[id];
        accrue(pool, id);
    }

    /// @notice update pool state to accrue interest since the last time accrue() was called
    function accrue(PoolData storage pool, uint256 id) internal {
        uint256 interestAccrued = IRateModel(pool.rateModel).interestAccrued(
            pool.lastUpdated, pool.totalBorrows.assets, pool.totalAssets.assets
        );

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

    /// @notice mint borrow shares and send borrowed assets to the borrowing position
    /// @dev only callable by the position manager
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

        emit Borrow(position, asset, amt);
    }

    /// @notice repay borrow shares
    /// @dev only callable by position manager, assume assets have already been sent to the pool
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

        emit Repay(position, pool.asset, amt);

        // return the remaining position debt, denominated in borrow shares
        return (borrowSharesOf[poolId][position] -= borrowShares);
    }

    /*//////////////////////////////////////////////////////////////
                           Initialize Pool
    //////////////////////////////////////////////////////////////*/

    function initializePool(
        address owner,
        address asset,
        address rateModel,
        uint128 interestFee,
        uint128 originationFee,
        uint128 poolCap
    ) external returns (uint256 poolId) {
        poolId = uint256(keccak256(abi.encodePacked(owner, asset, rateModel, interestFee, originationFee)));

        if (ownerOf[poolId] != address(0)) revert Pool_PoolAlreadyInitialized(poolId);
        ownerOf[poolId] = owner;

        PoolData memory poolData = PoolData({
            asset: asset,
            rateModel: rateModel,
            poolCap: poolCap,
            lastUpdated: uint128(block.timestamp),
            interestFee: interestFee,
            originationFee: originationFee,
            isPaused: false,
            totalAssets: Uint128Pair(0, 0),
            totalBorrows: Uint128Pair(0, 0)
        });

        poolDataFor[poolId] = poolData;

        emit PoolInitialized(poolId, owner, asset);
        emit RateModelUpdated(poolId, rateModel);
        emit InterestFeeSet(poolId, interestFee);
        emit OriginationFeeSet(poolId, originationFee);
        emit PoolCapSet(poolId, poolCap);
    }

    /*//////////////////////////////////////////////////////////////
                           Only Pool Owner
    //////////////////////////////////////////////////////////////*/

    function togglePause(uint256 poolId) external {
        if (msg.sender != ownerOf[poolId]) revert Pool_OnlyPoolOwner(poolId, msg.sender);
        PoolData storage pool = poolDataFor[poolId];
        pool.isPaused = !pool.isPaused;
        emit PoolPauseToggled(poolId, pool.isPaused);
    }

    function setPoolCap(uint256 poolId, uint128 poolCap) external {
        if (msg.sender != ownerOf[poolId]) revert Pool_OnlyPoolOwner(poolId, msg.sender);
        poolDataFor[poolId].poolCap = poolCap;
        emit PoolCapSet(poolId, poolCap);
    }

    function requestRateModelUpdate(uint256 poolId, address rateModel) external {
        if (msg.sender != ownerOf[poolId]) revert Pool_OnlyPoolOwner(poolId, msg.sender);
        RateModelUpdate memory rateModelUpdate =
            RateModelUpdate({rateModel: rateModel, validAfter: block.timestamp + TIMELOCK_DURATION});

        rateModelUpdateFor[poolId] = rateModelUpdate;

        emit RateModelUpdateRequested(poolId, rateModel);
    }

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

    function rejectRateModelUpdate(uint256 poolId) external {
        if (msg.sender != ownerOf[poolId]) revert Pool_OnlyPoolOwner(poolId, msg.sender);
        emit RateModelUpdateRejected(poolId, rateModelUpdateFor[poolId].rateModel);
        delete rateModelUpdateFor[poolId];
    }
}
