// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// types
import {IRateModel} from "./interfaces/IRateModel.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
// libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// contracts
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

contract Pool is OwnableUpgradeable, PausableUpgradeable, ERC4626Upgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IRateModel public rateModel;
    address immutable positionManager;

    uint256 public lastUpdated; // last time ping() was called
    uint256 public originationFee; // accrued to pool owner

    uint256 public totalBorrows; // cached total pool debt, call getBorrows() for up to date value
    uint256 public totalBorrowShares;

    mapping(address position => uint256 borrowShares) borrowSharesOf;

    error ZeroShares();
    error PositionManagerOnly();

    constructor(address _positionManager) {
        // written to only once when we deploy the initial impl
        positionManager = _positionManager;
        _disableInitializers();
    }

    function initialize(address asset, string memory _name, string memory _symbol) public initializer {
        OwnableUpgradeable.__Ownable_init(msg.sender);
        PausableUpgradeable.__Pausable_init();
        ERC20Upgradeable.__ERC20_init(_name, _symbol);
        ERC4626Upgradeable.__ERC4626_init(IERC20(asset));
    }

    // Pool Actions

    /// @return borrowShares the amount of shares minted
    function borrow(address position, uint256 amt) external whenNotPaused returns (uint256 borrowShares) {
        if (msg.sender != positionManager) revert PositionManagerOnly();
        ping(); // accrue pending interest

        // update borrows
        borrowShares = convertAssetToBorrowShares(amt);
        if (borrowShares == 0) revert ZeroShares();
        // update total pool debt, notional
        totalBorrows += amt;
        // update total pool debt, shares
        totalBorrowShares += borrowShares;
        // update position debt, shares
        borrowSharesOf[position] += borrowShares;

        // accrue origination fee
        uint256 fee = amt.mulDiv(originationFee, 1e18, Math.Rounding.Floor);
        // send origination fee to owner
        IERC20(asset()).safeTransfer(owner(), fee);
        // send borrowed assets to position
        IERC20(asset()).safeTransfer(position, amt - fee);
    }

    /// @dev assume assets have already been transferred successfully in the same txn
    /// @return the remaining shares owned in the position
    function repay(address position, uint256 amt) external returns (uint256) {
        if (msg.sender != positionManager) revert PositionManagerOnly();
        // accrue pending interest
        ping();

        // update borrows
        uint256 borrowShares = convertAssetToBorrowShares(amt);
        if (borrowShares == 0) revert ZeroShares();

        // update total pool debt, notional
        totalBorrows -= amt;
        // update total pool debt, shares
        totalBorrowShares -= borrowShares;
        // remaining position debt, in shares
        return (borrowSharesOf[position] -= borrowShares);
    }

    // View Functions

    /// @notice fetch total notional pool borrows
    function getBorrows() public view returns (uint256) {
        return totalBorrows
            + rateModel.interestAccrued(lastUpdated, totalBorrows, IERC20(asset()).balanceOf(address(this)));
    }

    /// @notice fetch total notional pool borrows for a given position
    function getBorrowsOf(address position) public view returns (uint256) {
        return convertBorrowSharesToAsset(borrowSharesOf[position]);
    }

    /// @notice accrue pending interest and update pool state
    function ping() public {
        totalBorrows = getBorrows();
        lastUpdated = block.timestamp;
    }

    /// @notice return total notional assets managed by pool, including lent out assets
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + getBorrows();
    }

    /// @notice convert notional asset amount to borrow shares
    function convertAssetToBorrowShares(uint256 amt) internal view returns (uint256) {
        return totalBorrowShares == 0 ? amt : amt.mulDiv(totalBorrowShares, getBorrows(), Math.Rounding.Ceil);
    }

    /// @notice convert borrow shares to notional asset amount
    function convertBorrowSharesToAsset(uint256 amt) internal view returns (uint256) {
        return totalBorrowShares == 0 ? amt : amt.mulDiv(getBorrows(), totalBorrowShares, Math.Rounding.Floor);
    }

    // ERC4626 Functions

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        ping();
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256) {
        ping();
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        ping();
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        ping();
        return super.redeem(shares, receiver, owner);
    }

    // Admin Functions

    function setRateModel(address _rateModel) external onlyOwner {
        rateModel = IRateModel(_rateModel);
    }

    function setOriginationFee(uint256 _originationFee) external onlyOwner {
        originationFee = _originationFee;
    }
}
