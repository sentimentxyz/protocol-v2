// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRateModel} from "./interfaces/IRateModel.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
import {IPool} from "./interfaces/IPool.sol";

import {FixedPointMathLib} from "lib/solmate/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {ERC6909} from "lib/solmate/src/tokens/ERC6909.sol";
import {Owned} from "lib/solmate/src/auth/Owned.sol";

contract Pool is Owned(msg.sender), ERC6909, IPool {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    uint256 public constant TIMELOCK_DURATION = 24 * 60 * 60; // 24 hours

    // position manager associated with this pool
    address immutable positionManager;

    // privileged address to modify protocol fees
    address immutable FEE_ADMIN;

    struct RateModelUpdate {
        address rateModel;
        uint256 validAfter;
    }

    RateModelUpdate public rateModelUpdate;

    /*//////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/

    error Pool_NoRateModelUpdate(address pool);
    error Pool_RateModelUpdateTimelock(address pool);
    error Pool_ZeroSharesRepay(address pool, uint256 amt);
    error Pool_ZeroSharesBorrow(address pool, uint256 amt);
    error Pool_ZeroSharesDeposit(address pool, uint256 amt);
    error Pool_OnlyPositionManager(address pool, address sender);

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    struct Fraction {
        uint128 assets;
        uint128 shares;
    }

    struct PoolData {
        address asset;
        address rateModel;
        uint128 interestFee;
        uint128 originationFee;
        uint128 lastUpdated;
        Fraction assets;
        Fraction borrows;
        mapping(uint256 => uint256) borrowSharesOf;
    }

    mapping(uint256 => PoolData) public poolData;

    constructor(address _positionManager, address _feeAdmin) {
        // stored only once when we deploy the initial implementation
        // does not need to be update or initialized by clones
        positionManager = _positionManager;
        FEE_ADMIN = _feeAdmin;
    }

    /*//////////////////////////////////////////////////////////////
                        Public View Functions
    //////////////////////////////////////////////////////////////*/

    function convertToShares(Fraction memory frac, uint256 assets) public pure returns (uint256 shares) {
        shares = assets.mulDivDown(frac.shares, frac.assets);
    }

    function convertToAssets(Fraction memory frac, uint256 shares) public pure returns (uint256 assets) {
        assets = shares.mulDivDown(frac.assets, frac.shares);
    }

    /*//////////////////////////////////////////////////////////////
                          Lending Functionality
    //////////////////////////////////////////////////////////////*/
    function deposit(uint256 poolId, uint256 assets, address receiver) public returns (uint256 shares) {
        PoolData storage pool = poolData[poolId];

        // update state to accrue interest since the last time accrue() was called
        accrue(pool, poolId);

        // Check for rounding error since we round down in previewDeposit.
        require((shares = convertToShares(pool.assets, assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        ERC20(pool.asset).safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, poolId, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function redeem(uint256 poolId, uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        PoolData storage pool = poolData[poolId];

        // update state to accrue interest since the last time accrue() was called
        accrue(pool, poolId);

        if (msg.sender != owner && !isOperator[owner][msg.sender]) {
            uint256 allowed = allowance[owner][msg.sender][poolId];
            if (allowed != type(uint256).max) allowance[owner][msg.sender][poolId] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = convertToAssets(pool.assets, shares)) != 0, "ZERO_ASSETS");

        _burn(owner, poolId, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        ERC20(pool.asset).safeTransfer(receiver, assets);
    }

    /*//////////////////////////////////////////////////////////////
                             Pool Actions
    //////////////////////////////////////////////////////////////*/

    function accrue(uint256 id) external {
        PoolData storage pool = poolData[id];
        accrue(pool, id);
    }

    /// @notice update pool state to accrue interest since the last time accrue() was called
    function accrue(PoolData storage pool, uint256 id) internal {
        uint256 interestAccrued =
            IRateModel(pool.rateModel).interestAccrued(pool.lastUpdated, pool.borrows.assets, pool.assets.assets);

        if (interestAccrued != 0) {
            // [ROUND] floor fees in favor of pool lenders
            uint256 feeAssets = interestAccrued.mulDivDown(pool.interestFee, 1e18);

            // totalAssets() - feeAssets
            uint256 totalAssetExFees = pool.assets.assets + interestAccrued - feeAssets;

            // [ROUND] round down in favor of pool lenders
            uint256 feeShares = feeAssets.mulDivDown(pool.assets.shares, totalAssetExFees + 1);

            _mint(FEE_ADMIN, id, feeShares);
        }

        // update cached notional borrows to current borrow amount
        pool.borrows.assets += uint128(interestAccrued);

        // store a timestamp for this accrue() call
        // used to compute the pending interest next time accrue() is called
        pool.lastUpdated = uint128(block.timestamp);
    }

    /// @notice mint borrow shares and send borrowed assets to the borrowing position
    /// @dev only callable by the position manager
    /// @param position the position to mint shares to
    /// @param to the address to send the borrowed assets to
    /// @param amt the amount of assets to borrow, denominated in notional asset units
    /// @return borrowShares the amount of shares minted
    function borrow(uint256 poolId, uint256 position, address to, uint256 amt)
        external
        returns (uint256 borrowShares)
    {
        PoolData storage pool = poolData[poolId];

        // revert if the caller is not the position manager
        if (msg.sender != positionManager) revert Pool_OnlyPositionManager(address(this), msg.sender);

        // update state to accrue interest since the last time accrue() was called
        accrue(pool, poolId);

        // compute borrow shares equivalant for notional borrow amt
        // [ROUND] round up shares minted, to ensure they capture the borrowed amount
        borrowShares = convertToShares(pool.borrows, amt);

        // revert if borrow amt is too small
        if (borrowShares == 0) revert Pool_ZeroSharesBorrow(address(this), amt);

        // update total pool debt, denominated in notional asset units and shares
        pool.borrows.assets += uint128(amt);
        pool.borrows.shares += uint128(borrowShares);

        // update position debt, denominated in borrow shares
        pool.borrowSharesOf[position] += borrowShares;

        // compute origination fee amt
        // [ROUND] origination fee is rounded down, in favor of the borrower
        uint256 fee = amt.mulDivDown(pool.originationFee, 1e18);

        address asset = pool.asset;
        // send origination fee to owner
        ERC20(asset).safeTransfer(owner, fee);

        // send borrowed assets to position
        ERC20(asset).safeTransfer(to, amt - fee);

        emit Borrow(position, asset, amt);
    }

    /// @notice repay borrow shares
    /// @dev only callable by position manager, assume assets have already been sent to the pool
    /// @param position the position for which debt is being repaid
    /// @param amt the notional amount of debt asset repaid
    /// @return remainingShares remaining debt in borrow shares owed by the position
    function repay(uint256 poolId, uint256 position, uint256 amt) external returns (uint256 remainingShares) {
        PoolData storage pool = poolData[poolId];
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
        uint256 borrowShares = convertToShares(pool.borrows, amt);

        // revert if repaid amt is too small
        if (borrowShares == 0) revert Pool_ZeroSharesRepay(address(this), amt);

        // update total pool debt, denominated in notional asset units, and shares
        pool.borrows.assets -= uint128(amt);
        pool.borrows.shares -= uint128(borrowShares);

        emit Repay(position, pool.asset, amt);

        // return the remaining position debt, denominated in borrow shares
        return (pool.borrowSharesOf[position] -= borrowShares);
    }
}
