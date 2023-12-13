// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract SuperPool is Ownable, Pausable, ERC4626 {
    mapping(address => uint256) public poolCap;

    event PoolCapSet(address indexed pool, uint256 amt);
    event PoolDeposit(address indexed pool, uint256 assets);
    event PoolWithdraw(address indexed pool, uint256 assets);

    constructor(IERC20 asset, string memory name_, string memory symbol_)
        Ownable(msg.sender)
        ERC20(name_, symbol_)
        ERC4626(asset)
    {}

    function setPoolCap(address pool, uint256 assets) external onlyOwner {
        poolCap[pool] = assets;
        emit PoolCapSet(pool, assets);
    }

    function poolDeposit(address pool, uint256 assets) external onlyOwner {
        IERC20(this.asset()).approve(address(pool), assets);
        IERC4626(pool).deposit(assets, address(this));
        require(IERC4626(pool).balanceOf(address(this)) <= poolCap[pool]);
        emit PoolDeposit(pool, assets);
    }

    function poolWithdraw(address pool, uint256 assets) external onlyOwner {
        IERC4626(pool).withdraw(assets, address(this), address(this));
        emit PoolWithdraw(pool, assets);
    }
}
