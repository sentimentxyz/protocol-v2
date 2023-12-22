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
    mapping(IERC4626 => uint256) public poolCap;
    /// Actually stores poolIdx + 1
    mapping(IERC4626 => uint256) internal _poolIdx;
    /// List of pools
    IERC4626[] public pools;

    /// The cumaltive deposit cap for all pools
    uint256 public totalPoolCap;

    event PoolCapSet(address indexed pool, uint256 amt);
    event PoolDeposit(address indexed pool, uint256 assets);
    event PoolWithdraw(address indexed pool, uint256 assets);

    constructor(IERC20 _asset, string memory _name, string memory _symbol, address owner)
        Ownable(owner)
        ERC20(_name, _symbol)
        ERC4626(_asset)
    {}

    ////////////////////////// Only Owner //////////////////////////
    function setPoolCap(address _pool, uint256 assets) external onlyOwner {
        IERC4626 pool = IERC4626(_pool);

        require(pool.previewRedeem(pool.balanceOf(address(this))) <= assets, "SuperPool: cap too low");

        if (assets == 0 && poolCap[pool] == 0) {
            // nothing to do
            return;
        }

        // check that weve seen this pool before
        if (_poolIdx[pool] == 0) {
            pools.push(IERC4626(pool));

            _poolIdx[pool] = pools.length;
        }

        // add or remove cumaltive deposit cap
        uint256 current = poolCap[pool];
        if (assets > current) {
            totalPoolCap += assets - current;
        } else {
            totalPoolCap -= current - assets;
        }

        poolCap[pool] = assets;

        // remove the pool if we set the cap to 0
        if (assets == 0) {
            uint256 len = pools.length;
            
            // get the actual index of the pool
            uint256 toRemoveIdx = poolIdx(pool);

            if (toRemoveIdx == len - 1) {
                // if the pool is the last pool, we can just pop it off
                pools.pop();
                _poolIdx[pool] = 0;
            } else {
                // Repalce the pool to remove with the last pool
                pools[toRemoveIdx] = pools[pools.length - 1];

                // copy the last pool address so we can adjust its index 
                IERC4626 lastPool = pools[len - 1];
                _poolIdx[lastPool] = toRemoveIdx + 1;

                pools.pop();
            }
        }

        emit PoolCapSet(_pool, assets);
    }

    function poolDeposit(address _pool, uint256 assets) external onlyOwner {
        IERC4626 pool = IERC4626(_pool);

        IERC20(this.asset()).approve(address(pool), assets);
        IERC4626(pool).deposit(assets, address(this));
        require(IERC4626(pool).balanceOf(address(this)) <= poolCap[pool]);
        emit PoolDeposit(_pool, assets);
    }

    function poolWithdraw(address pool, uint256 assets) external onlyOwner {
        IERC4626(pool).withdraw(assets, address(this), address(this));
        emit PoolWithdraw(pool, assets);
    }

    ////////////////////////// Deposit/Withdraw //////////////////////////



    ////////////////////////// Overrides //////////////////////////
    function totalAssets() public view override returns (uint256 total) {
        uint256 len = pools.length;
        for (uint256 i = 0; i < len; i++) {
            IERC4626 pool = IERC4626(pools[i]);

            uint256 sharesBalance = pool.balanceOf(address(this));
            total += pool.previewRedeem(sharesBalance);
        }
    }

    function maxDeposit(address) public view override returns (uint256) {
        return totalPoolCap;
    }

    function maxMint(address) public view override returns (uint256) {
        uint256 _maxDeposit = maxDeposit(address(0));
        return previewDeposit(_maxDeposit);
    }

    ////////////////////////// Helpers //////////////////////////

    /// Warning: reverts if pool is not in the list
    function poolIdx(IERC4626 pool) internal view returns (uint256) {
        return _poolIdx[pool] - 1;
    }

    function allPools() external view returns (IERC4626[] memory) {
        return pools;
    }
}
