// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {Registry} from "./Registry.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IRateModel} from "./interfaces/IRateModel.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
// libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// contracts
import {ERC6909} from "./lib/ERC6909.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Pool is Ownable, ERC6909, IPool {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                             Data Structs
    //////////////////////////////////////////////////////////////*/

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
        Uint128Pair totalAssets;
        Uint128Pair totalBorrows;
    }

    struct RateModelUpdate {
        address rateModel;
        uint256 validAfter;
    }

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    uint256 public constant TIMELOCK_DURATION = 24 * 60 * 60; // 24 hours
    // registry key for position manager derived from keccak(SENTIMENT_POSITION_MANAGER_KEY)
    bytes32 public constant SENTIMENT_POSITION_MANAGER_KEY =
        0xd4927490fbcbcafca716cca8e8c8b7d19cda785679d224b14f15ce2a9a93e148;

    Registry public immutable REGISTRY;

    // address that receives protocol fees
    address public feeRecipient;
    address public positionManager;

    mapping(uint256 poolId => address poolOwner) public ownerOf;
    mapping(uint256 poolId => PoolData data) public poolDataFor;
    mapping(uint256 poolId => RateModelUpdate rateModelUpdate) public rateModelUpdateFor;
    mapping(uint256 poolId => mapping(address position => uint256 borrowShares)) public borrowSharesOf;

    /*//////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/

    error Pool_AlreadyInitialized();
    error Pool_NoRateModelUpdate(uint256 poolId);
    error Pool_PoolAlreadyInitialized(uint256 poolId);
    error Pool_ZeroSharesRepay(address pool, uint256 amt);
    error Pool_ZeroSharesBorrow(address pool, uint256 amt);
    error Pool_ZeroSharesDeposit(address pool, uint256 amt);
    error Pool_OnlyPoolOwner(uint256 poolId, address sender);
    error Pool_OnlyPositionManager(address pool, address sender);
    error Pool_TimelockPending(uint256 poolId, uint256 currentTimestamp);

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor(address registry_, address feeRecipient_) Ownable(msg.sender) {
        feeRecipient = feeRecipient_;
        REGISTRY = Registry(registry_);
    }

    function updateFromRegistry() external {
        positionManager = REGISTRY.addressFor(SENTIMENT_POSITION_MANAGER_KEY);
    }

    /*//////////////////////////////////////////////////////////////
                        Public View Functions
    //////////////////////////////////////////////////////////////*/

    function getAssetsOf(uint256 poolId, address guy) public view returns (uint256) {}

    function getBorrowsOf(uint256 poolId, address position) public view returns (uint256) {}

    function getTotalBorrows(uint256 poolId) public view returns (uint256) {
        return poolDataFor[poolId].totalBorrows.assets;
    }

    function getRateModelFor(uint256 poolId) public view returns (address) {
        return poolDataFor[poolId].rateModel;
    }

    function getPoolAssetFor(uint256 poolId) public view returns (address) {
        return poolDataFor[poolId].asset;
    }

    function convertToShares(Uint128Pair memory frac, uint256 assets) public pure returns (uint256 shares) {
        shares = assets.mulDiv(frac.shares, frac.assets);
    }

    function convertToAssets(Uint128Pair memory frac, uint256 shares) public pure returns (uint256 assets) {
        assets = shares.mulDiv(frac.assets, frac.shares);
    }

    /*//////////////////////////////////////////////////////////////
                          Lending Functionality
    //////////////////////////////////////////////////////////////*/
    function deposit(uint256 poolId, uint256 assets, address receiver) public returns (uint256 shares) {
        PoolData storage pool = poolDataFor[poolId];

        // update state to accrue interest since the last time accrue() was called
        accrue(pool, poolId);

        // Check for rounding error since we round down in previewDeposit.
        require((shares = convertToShares(pool.totalAssets, assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        IERC20(pool.asset).safeTransferFrom(msg.sender, address(this), assets);

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
        require((assets = convertToAssets(pool.totalAssets, shares)) != 0, "ZERO_ASSETS");

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

            // totalAssets() - feeAssets
            uint256 totalAssetExFees = pool.totalAssets.assets + interestAccrued - feeAssets;

            // [ROUND] round down in favor of pool lenders
            uint256 feeShares = feeAssets.mulDiv(pool.totalAssets.shares, totalAssetExFees + 1);

            _mint(feeRecipient, id, feeShares);
        }

        // update cached notional borrows to current borrow amount
        pool.totalBorrows.assets += uint128(interestAccrued);

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

        // revert if the caller is not the position manager
        if (msg.sender != positionManager) revert Pool_OnlyPositionManager(address(this), msg.sender);

        // update state to accrue interest since the last time accrue() was called
        accrue(pool, poolId);

        // compute borrow shares equivalant for notional borrow amt
        // [ROUND] round up shares minted, to ensure they capture the borrowed amount
        borrowShares = convertToShares(pool.totalBorrows, amt);

        // revert if borrow amt is too small
        if (borrowShares == 0) revert Pool_ZeroSharesBorrow(address(this), amt);

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
        if (msg.sender != positionManager) revert Pool_OnlyPositionManager(address(this), msg.sender);

        // update state to accrue interest since the last time accrue() was called
        accrue(pool, poolId);

        // compute borrow shares equivalent to notional asset amt
        // [ROUND] burn fewer borrow shares, to ensure excess debt isn't pushed to others
        uint256 borrowShares = convertToShares(pool.totalBorrows, amt);

        // revert if repaid amt is too small
        if (borrowShares == 0) revert Pool_ZeroSharesRepay(address(this), amt);

        // update total pool debt, denominated in notional asset units, and shares
        pool.totalBorrows.assets -= uint128(amt);
        pool.totalBorrows.shares -= uint128(borrowShares);

        emit Repay(position, pool.asset, amt);

        // return the remaining position debt, denominated in borrow shares
        return (borrowSharesOf[poolId][position] -= borrowShares);
    }

    function initializePool(address owner, bytes32 salt, PoolData calldata poolData) external {
        uint256 poolId = uint256(keccak256(abi.encodePacked(owner, salt)));
        if (ownerOf[poolId] != address(0)) revert Pool_PoolAlreadyInitialized(poolId);
        ownerOf[poolId] = owner;
        poolDataFor[poolId] = poolData;

        emit PoolInitialized(owner, poolId, poolData);
    }

    /*//////////////////////////////////////////////////////////////
                           Only Pool Owner
    //////////////////////////////////////////////////////////////*/

    modifier onlyPoolOwner(uint256 poolId, address sender) {
        if (ownerOf[poolId] != sender) revert Pool_OnlyPoolOwner(poolId, sender);
        _;
    }

    function transferPoolOwnership(uint256 poolId, address newOwner) external onlyPoolOwner(poolId, msg.sender) {
        ownerOf[poolId] = newOwner;

        emit PoolOwnerSet(poolId, newOwner);
    }

    function requestRateModelUpdate(uint256 poolId, address rateModel) external onlyPoolOwner(poolId, msg.sender) {
        rateModelUpdateFor[poolId] =
            RateModelUpdate({rateModel: rateModel, validAfter: block.timestamp + TIMELOCK_DURATION});

        emit RateModelUpdateRequested(poolId, rateModel);
    }

    function acceptRateModelUpdate(uint256 poolId) external onlyPoolOwner(poolId, msg.sender) {
        RateModelUpdate memory rateModelUpdate = rateModelUpdateFor[poolId];

        if (rateModelUpdate.validAfter == 0) revert Pool_NoRateModelUpdate(poolId);
        if (rateModelUpdate.validAfter > block.timestamp) revert Pool_TimelockPending(poolId, block.timestamp);

        poolDataFor[poolId].rateModel = rateModelUpdate.rateModel;

        emit RateModelUpdated(poolId, rateModelUpdate.rateModel);
    }

    function rejectRateModelUpdate(uint256 poolId) external onlyPoolOwner(poolId, msg.sender) {
        RateModelUpdate memory rateModelUpdate = rateModelUpdateFor[poolId];

        delete rateModelUpdateFor[poolId];

        emit RateModelUpdateRejected(poolId, rateModelUpdate.rateModel);
    }

    function setInterestFee(uint256 poolId, uint128 interestFee) external onlyPoolOwner(poolId, msg.sender) {
        poolDataFor[poolId].interestFee = interestFee;

        emit InterestFeeSet(poolId, interestFee);
    }

    function setPoolCap(uint256 poolId, uint128 poolCap) external onlyPoolOwner(poolId, msg.sender) {
        poolDataFor[poolId].poolCap = poolCap;

        emit PoolCapSet(poolId, poolCap);
    }

    function setOriginationFee(uint256 poolId, uint128 originationFee) external onlyPoolOwner(poolId, msg.sender) {
        poolDataFor[poolId].originationFee = originationFee;

        emit OriginationFeeSet(poolId, originationFee);
    }
}
