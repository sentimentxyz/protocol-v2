// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract SuperPool is Ownable, Pausable, ERC4626 {
    /// This is basically an iterable mapping
    /// may be worth it to extract out
    mapping(address => uint256) public poolCap;
    /// Actually stores poolIdx + 1
    mapping(address => uint256) internal _poolIdx;
    IERC4626[] public pools;

    event PoolCapSet(address indexed pool, uint256 amt);
    event PoolDeposit(address indexed pool, uint256 assets);
    event PoolWithdraw(address indexed pool, uint256 assets);

    constructor(IERC20 _asset, string memory _name, string memory _symbol)
        Ownable(msg.sender)
        ERC20(_name, _symbol)
        ERC4626(_asset)
    {}

    ////////////////////////// Only Owner //////////////////////////
    function setPoolCap(address pool, uint256 assets) external onlyOwner {
        if (assets == 0 && poolCap[pool] == 0) {
            // nothing to do
            return;
        }

        // check that weve seen this pool before
        if (_poolIdx[pool] == 0) {
            pools.push(IERC4626(pool));
            _poolIdx[pool] = pools.length;
        }

        poolCap[pool] = assets;

        // remove the pool if we set the cap to 0
        if (assets == 0) {
            uint256 len = pools.length;
            
            // get the actual index of the pool
            uint256 toRemoveIdx = poolIdx(pool);

            // Repalce the pool to remove with the last pool
            pools[toRemoveIdx] = pools[pools.length - 1];

            // copy the last pool address so we can adjust its index 
            address lastPool = pools[len - 1];
            poolIdx[lastPool] = toRemoveIdx;

            pools.pop();

        }

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

    ////////////////////////// Deposit/Withdraw Overrides //////////////////////////



    ////////////////////////// General Overrides //////////////////////////
    function totalAssets() public view override returns (uint256 total) {
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 sharesBalance = pools[i].balanceOf(address(this));
            total += pools[i].previewRedeem(sharesBalance);
        }
    }

    ////////////////////////// Helpers //////////////////////////

    /// Warning: reverts if pool is not in the list
    function poolIdx(address pool) public view returns (uint256) {
        return _poolIdx[pool] - 1;
    }
}
