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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract Pool is Ownable, Pausable, ERC4626 {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IRateModel public rateModel;
    address public positionManager;

    uint256 public lastUpdated; // last time ping() was called
    uint256 public originationFee; // accrued to pool owner

    uint256 public totalBorrows; // cached total pool debt, call getBorrows() for up to date value
    uint256 public totalBorrowShares;

    mapping(address position => uint256 borrowShares) borrowSharesOf;

    error ZeroShares();
    error PositionManagerOnly();

    constructor(IERC20 asset, string memory name_, string memory symbol_)
        Ownable(msg.sender)
        ERC20(name_, symbol_)
        ERC4626(asset)
    {}

    // Pool Actions

    function borrow(address position, uint256 amt) external whenNotPaused {
        if (msg.sender != positionManager) revert PositionManagerOnly();
        ping(); // accrue pending interest

        // update borrows
        uint256 borrowShares = convertAssetToBorrowShares(amt);
        if (borrowShares == 0) revert ZeroShares();
        totalBorrows += amt; // update total pool debt, notional
        totalBorrowShares += borrowShares; // update total pool debt, shares
        borrowSharesOf[position] += borrowShares; // update position debt, shares

        // accrue origination fee
        uint256 fee = amt.mulDiv(originationFee, 1e18, Math.Rounding.Floor);
        IERC20(asset()).safeTransfer(owner(), fee); // send origination fee to owner
        IERC20(asset()).safeTransfer(position, amt - fee); // send borrowed assets to position
    }

    /// @dev assume assets have already been transferred successfully in the same txn
    function repay(address position, uint256 amt) external returns (uint256) {
        if (msg.sender != positionManager) revert PositionManagerOnly();
        ping(); // accrue pending interest

        // update borrows
        uint256 borrowShares = convertAssetToBorrowShares(amt);
        if (borrowShares == 0) revert ZeroShares();
        totalBorrows -= amt; // update total pool debt, notional
        totalBorrowShares -= borrowShares; // update total pool debt, shares
        return (borrowSharesOf[position] -= borrowShares); // remaining position debt, in shares
    }

    // View Functions

    /// @notice fetch total notional pool borrows
    function getBorrows() public view returns (uint256) {
        return totalBorrows.mulDiv(1e18 + rateModel.rateFactor(), 1e18, Math.Rounding.Ceil);
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
        return totalBorrowShares == 0 ? 0 : amt.mulDiv(totalBorrowShares, getBorrows(), Math.Rounding.Ceil);
    }

    /// @notice convert borrow shares to notional asset amount
    function convertBorrowSharesToAsset(uint256 amt) internal view returns (uint256) {
        return totalBorrowShares == 0 ? 0 : amt.mulDiv(getBorrows(), totalBorrowShares, Math.Rounding.Floor);
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

    function setPositionManager(address _positionManager) external onlyOwner {
        positionManager = _positionManager;
    }

    function setRateModel(IRateModel _rateModel) external onlyOwner {
        rateModel = _rateModel;
    }

    function setOriginationFee(uint256 _originationFee) external onlyOwner {
        originationFee = _originationFee;
    }

    // TODO pool caps?
}
