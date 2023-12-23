// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IRateModel} from "./IRateModel.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract Pool is Ownable, Pausable, ERC4626 {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IRateModel public rateModel;
    address public positionManager;

    uint256 public lastUpdated;
    uint256 public originationFee;

    /// @dev cached total notional borrows, call getBorrows() for updated value
    uint256 public totalBorrows;
    uint256 public totalBorrowShares;
    mapping(address => uint256) borrowSharesOf;

    error ZeroShares();
    error PositionManagerOnly();

    constructor(IERC20 asset, string memory name_, string memory symbol_)
        Ownable(msg.sender)
        ERC20(name_, symbol_)
        ERC4626(asset)
    {}

    function borrow(address position, uint256 amt) external whenNotPaused {
        if (msg.sender != positionManager) revert PositionManagerOnly();
        ping();
        uint256 borrowShares = convertAssetToBorrowShares(amt);
        if (borrowShares == 0) revert ZeroShares();
        borrowSharesOf[position] += borrowShares;
        totalBorrows += amt;
        uint256 fee = amt.mulDiv(originationFee, 1e18, Math.Rounding.Floor);
        IERC20(asset()).safeTransfer(owner(), fee);
        IERC20(asset()).safeTransfer(position, amt - fee);
    }

    /// @dev assume assets have already been transferred successfully in the same txn
    function repay(address position, uint256 amt) external {
        if (msg.sender != positionManager) revert PositionManagerOnly();
        ping();
        uint256 borrowShares = convertAssetToBorrowShares(amt);
        if (borrowShares == 0) revert ZeroShares();
        borrowSharesOf[position] -= borrowShares;
        totalBorrowShares -= borrowShares;
        totalBorrows -= amt;
    }

    function getBorrows() public view returns (uint256) {
        return totalBorrows.mulDiv(1e18 + rateModel.rateFactor(), 1e18, Math.Rounding.Ceil);
    }

    function ping() public {
        totalBorrows = getBorrows();
        lastUpdated = block.timestamp;
    }

    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + getBorrows();
    }

    function convertAssetToBorrowShares(uint256 amt) internal view returns (uint256) {
        return totalBorrowShares == 0 ? 0 : amt.mulDiv(totalBorrowShares, getBorrows(), Math.Rounding.Ceil);
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
