// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Imports
//////////////////////////////////////////////////////////////*/

// types
import {IRateModel} from "./interface/IRateModel.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
// libraries
import {Errors} from "src/lib/Errors.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// contracts
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

/*//////////////////////////////////////////////////////////////
                            Events
//////////////////////////////////////////////////////////////*/

/// @dev emitted on repay()
/// @param position address to position for which debt was repaid
/// @param asset debt asset for this pool
/// @param amount amount of debt repaid, in debt asset units
event Repay(address indexed position, address indexed asset, uint256 amount);

/// @dev emitted on borrow()
/// @param position address to position which borrowed funds
/// @param asset debt asset for this pool
/// @param amount amount of funds borrowed, in debt asset units
event Borrow(address indexed position, address indexed asset, uint256 amount);

/*//////////////////////////////////////////////////////////////
                            Pool
//////////////////////////////////////////////////////////////*/

contract Pool is OwnableUpgradeable, PausableUpgradeable, ERC4626Upgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    // interest rate model associated with this pool
    IRateModel public rateModel;

    // position manager associated with this pool
    address immutable positionManager;

    // last time ping() was called
    // used to track pending interest accruals
    uint256 public lastUpdated;

    // origination fees are accrued to the pool manager on every borrow
    // a part of the borrow amount is sent to the pool manager as fees
    uint256 public originationFee;

    // stores total assets lent out by the pool, in notional units
    // this value is cached and doesn't account for accrued interest
    // call getBorrows() to fetch the updated total borrows
    uint256 public totalBorrows;

    // stores total funds lent out by the pool, denominated in borrow shares
    // borrow shares use a different base and are not related to erc4626 shares for this pool
    uint256 public totalBorrowShares;

    uint256 public poolCap;

    // fetch debt for a given position, denominated in borrow shares
    // borrow shares use a different base and are not related to erc4626 shares for this pool
    mapping(address position => uint256 borrowShares) borrowSharesOf;

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor(address _positionManager) {
        // stored only once when we deploy the initial implementation
        // does not need to be update or initialized by clones
        positionManager = _positionManager;
        _disableInitializers();
    }

    function initialize(address _asset, string memory _name, string memory _symbol) public initializer {
        OwnableUpgradeable.__Ownable_init(msg.sender);
        PausableUpgradeable.__Pausable_init();
        ERC20Upgradeable.__ERC20_init(_name, _symbol);
        ERC4626Upgradeable.__ERC4626_init(IERC20(_asset));
    }

    /*//////////////////////////////////////////////////////////////
                        Public View Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice fetch current total pool borrows, denominated in notional asset units
    function getTotalBorrows() public view returns (uint256) {
        // total current borrows = cached total borrows + pending interest
        return totalBorrows
            + rateModel.interestAccrued(lastUpdated, totalBorrows, IERC20(asset()).balanceOf(address(this)));
    }

    /// @notice fetch pool borrows for a given position, denominated in notional asset units
    /// @param position the position to fetch borrows for
    function getBorrowsOf(address position) public view returns (uint256) {
        // fetch borrow shares owed by given position
        // convert borrow shares to notional asset units
        return convertBorrowSharesToAsset(borrowSharesOf[position]);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 View Overrides
    //////////////////////////////////////////////////////////////*/

    /// @notice total assets managed by the pool, denominated in notional asset units
    function totalAssets() public view override returns (uint256) {
        // total assets = current total borrows + idle assets in pool
        return getTotalBorrows() + IERC20(asset()).balanceOf(address(this));
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxDeposit(address) public view override returns (uint256) {
        return poolCap - totalAssets();
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxMint(address) public view override returns (uint256) {
        return previewDeposit(maxDeposit(address(0)));
    }

    /*//////////////////////////////////////////////////////////////
                          ERC4626 Overrides
    //////////////////////////////////////////////////////////////*/

    // pool state is updated after accrual of pending interest before any erc4626 call
    // there is no internal change in the workings of these functions other than the above

    /// @inheritdoc ERC4626Upgradeable
    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        // update state to accrue interest since the last time ping() was called
        ping();

        // inherited erc4626 call
        return ERC4626Upgradeable.deposit(assets, receiver);
    }

    /// @inheritdoc ERC4626Upgradeable
    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256) {
        // update state to accrue interest since the last time ping() was called
        ping();

        // inherited erc4626 call
        return ERC4626Upgradeable.mint(shares, receiver);
    }

    /// @inheritdoc ERC4626Upgradeable
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        // update state to accrue interest since the last time ping() was called
        ping();

        // inherited erc4626 call
        return ERC4626Upgradeable.withdraw(assets, receiver, owner);
    }

    /// @inheritdoc ERC4626Upgradeable
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        // update state to accrue interest since the last time ping() was called
        ping();

        // inherited erc4626 call
        return ERC4626Upgradeable.redeem(shares, receiver, owner);
    }

    /*//////////////////////////////////////////////////////////////
                             Pool Actions
    //////////////////////////////////////////////////////////////*/

    /// @notice update pool state to accrue interest since the last time ping() was called
    function ping() public {
        // update cached notional borrows to current borrow amount
        totalBorrows = getTotalBorrows();

        // store a timestamp for this ping() call
        // used to compute the pending interest next time ping() is called
        lastUpdated = block.timestamp;
    }

    /// @notice mint borrow shares and send borrowed assets to the borrowing position
    /// @dev only callable by the position manager
    /// @param position the position to mint shares to
    /// @param amt the amount of assets to borrow, denominated in notional asset units
    /// @return borrowShares the amount of shares minted
    function borrow(address position, uint256 amt) external whenNotPaused returns (uint256 borrowShares) {
        // revert if the caller is not the position manager
        if (msg.sender != positionManager) revert Errors.OnlyPositionManager();

        // update state to accrue interest since the last time ping() was called
        ping();

        // compute borrow shares equivalant for notional borrow amt
        borrowShares = convertAssetToBorrowShares(amt);

        // revert if borrow amt is too small
        if (borrowShares == 0) revert Errors.ZeroSharesBorrow();

        // update total pool debt, denominated in notional asset units
        totalBorrows += amt;

        // update total pool debt, denominated in borrow shares
        totalBorrowShares += borrowShares;

        // update position debt, denominated in borrow shares
        borrowSharesOf[position] += borrowShares;

        // compute origination fee amt
        uint256 fee = amt.mulDiv(originationFee, 1e18, Math.Rounding.Floor);

        // send origination fee to owner
        IERC20(asset()).safeTransfer(owner(), fee);

        // send borrowed assets to position
        IERC20(asset()).safeTransfer(position, amt - fee);

        emit Borrow(position, ERC4626Upgradeable.asset(), amt);
    }

    /// @notice repay borrow shares
    /// @dev only callable by position manager, assume assets have already been sent to the pool
    /// @param position the position for which debt is being repaid
    /// @param amt the notional amount of debt asset repaid
    /// @return remainingShares remaining debt in borrow shares owed by the position
    function repay(address position, uint256 amt) external returns (uint256 remainingShares) {
        // the only way to call repay() is through the position manager
        // PositionManager.repay() MUST transfer the assets to be repaid before calling Pool.repay()
        // this function assumes the transfer of assets was completed successfully

        // there is an implicit assumption that assets were transferred in the same txn lest
        // the call to Pool.repay() is not frontrun allowing debt repayment for another position

        // revert if the caller is not the position manager
        if (msg.sender != positionManager) revert Errors.OnlyPositionManager();

        // update state to accrue interest since the last time ping() was called
        ping();

        // compute borrow shares equivalent to notional asset amt
        uint256 borrowShares = convertAssetToBorrowShares(amt);

        // revert if repaid amt is too small
        if (borrowShares == 0) revert Errors.ZeroSharesRepay();

        // update total pool debt, denominated in notional asset units
        totalBorrows -= amt;

        // update total pool debt, denominated in borrow shares
        totalBorrowShares -= borrowShares;

        emit Repay(position, ERC4626Upgradeable.asset(), amt);

        // return the remaining position debt, denominated in borrow shares
        return (borrowSharesOf[position] -= borrowShares);
    }

    /*//////////////////////////////////////////////////////////////
                          Borrow Share Math
    //////////////////////////////////////////////////////////////*/

    /// @notice convert notional asset amount to borrow shares
    /// @param amt the amount of assets to convert to borrow shares
    /// @return the amount of shares
    function convertAssetToBorrowShares(uint256 amt) internal view returns (uint256) {
        // borrow shares = amt * totalBorrowShares / currentTotalBorrows
        // handle edge case for when borrows are zero by minting shares in 1:1 amt
        return totalBorrowShares == 0 ? amt : amt.mulDiv(totalBorrowShares, getTotalBorrows(), Math.Rounding.Ceil);
    }

    /// @notice convert borrow shares to notional asset amount
    /// @param amt the amount of shares to convert to assets
    /// @return the amount of assets
    function convertBorrowSharesToAsset(uint256 amt) internal view returns (uint256) {
        // notional asset amount = borrowSharesAmt * currenTotalBorrows / totalBorrowShares
        // handle edge case for when borrows are zero by minting shares in 1:1 amt
        return totalBorrowShares == 0 ? amt : amt.mulDiv(getTotalBorrows(), totalBorrowShares, Math.Rounding.Floor);
    }

    /*//////////////////////////////////////////////////////////////
                              Only Owner
    //////////////////////////////////////////////////////////////*/

    /// @notice set the rate model for the pool
    /// @notice callable only by the pool manager who is also the pool contract clone owner
    function setRateModel(address _rateModel) external onlyOwner {
        rateModel = IRateModel(_rateModel);
    }

    /// @notice set the origination fee for the pool
    /// @notice callable only by the pool manager who is also the pool contract clone owner
    function setOriginationFee(uint256 _originationFee) external onlyOwner {
        originationFee = _originationFee;
    }

    function setPoolCap(uint256 _poolCap) external onlyOwner {
        poolCap = _poolCap;
    }
}
