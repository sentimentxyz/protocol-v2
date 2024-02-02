// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface ISuperPool {
    // ERC20 Functions
    function decimals() external view returns (uint8);
    function name() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function symbol() external view returns (string memory);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    // ERC20 Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ERC4626 Functions
    function asset() external view returns (address assetTokenAddress); // debt asset
    function totalAssets() external view returns (uint256 totalManagedAssets); // include debt
    function convertToShares(uint256 assets) external view returns (uint256 shares);
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function previewDeposit(uint256 assets) external view returns (uint256 shares);
    function maxDeposit(address receiver) external view returns (uint256 maxAssets); // respect debt cap
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function previewMint(uint256 shares) external view returns (uint256 assets);
    function maxMint(address receiver) external view returns (uint256 maxShares); // respect debt cap
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    function maxWithdraw(address owner) external view returns (uint256 maxAssets);
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    function maxRedeem(address owner) external view returns (uint256 maxShares);
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    // ERC4626 Events
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    // SuperPool Functions
    // Only Owner
    function setPoolCap(address pool) external;
    function poolDeposit(address pool, uint256 amt) external;
    function poolWithdraw(address pool, uint256 amt) external;

    // Public
    function poolCap(address pool) external view returns (uint256);
    function pools() external view returns (IERC4626[] memory);

    function withdrawWithPath(uint256 assets, address reciever, uint256[] memory path)
        external
        returns (uint256 shares);
    function withdrawEnque(uint256 assets, address reciever) external returns (uint256 shares);
    function proceessWithdraw(uint256 assets, address reciever, uint256[] memory path)
        external
        returns (uint256 shares);
}
