// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {PoolCapMapping} from "src/lib/PoolCapMapping.sol";

contract SuperPool is Ownable, Pausable, ERC4626 {
    using PoolCapMapping for PoolCapMapping.PoolCapMappingStorage;

    /// An internal mapping of Pool => Pool Cap, incldudes an array of pools with non zero cap.
    PoolCapMapping.PoolCapMappingStorage internal poolCaps;

    /// The cumlative deposit cap for all pools
    uint256 public totalPoolCap;

    /// Privileged address allowed to allocate funds to and from pools on behalf of the owner
    address public allocator;

    event PoolCapSet(address indexed pool, uint256 amt);
    event PoolDeposit(address indexed pool, uint256 assets);
    event PoolWithdraw(address indexed pool, uint256 assets);

    error PoolCapTooLow();
    error OnlyAllocatorOrOwner();

    constructor(address _asset, string memory _name, string memory _symbol, address owner)
        Ownable(owner)
        ERC20(_name, _symbol)
        ERC4626(IERC20(_asset))
    {}

    ////////////////////////// Only Owner //////////////////////////

    function setPoolCap(address _pool, uint256 assets) external onlyOwner {
        IERC4626 pool = IERC4626(_pool);

        if (pool.previewRedeem(pool.balanceOf(address(this))) > assets) revert PoolCapTooLow();

        if (assets == 0 && poolCap(pool) == 0) {
            // nothing to do
            return;
        }

        // add or remove cumaltive deposit cap
        uint256 current = poolCap(pool);
        if (assets > current) {
            totalPoolCap += assets - current;
        } else {
            totalPoolCap -= current - assets;
        }

        poolCaps.set(pool, assets);

        emit PoolCapSet(_pool, assets);
    }

    function poolDeposit(address _pool, uint256 assets) external {
        if (msg.sender != allocator && msg.sender != owner()) revert OnlyAllocatorOrOwner();
        IERC4626 pool = IERC4626(_pool);

        IERC20(this.asset()).approve(address(pool), assets);
        IERC4626(pool).deposit(assets, address(this));
        require(IERC4626(pool).balanceOf(address(this)) <= poolCap(pool));
        emit PoolDeposit(_pool, assets);
    }

    function poolWithdraw(address pool, uint256 assets) external onlyOwner {
        _poolWithdraw(IERC4626(pool), assets);
    }

    function setAllocator(address _allocator) external onlyOwner {
        allocator = _allocator;
    }

    ////////////////////////// Withdraw //////////////////////////

    function withdrawWithPath(uint256 assets, uint256[] memory path) external whenNotPaused {
        _withdrawWithPath(assets, path);
        withdraw(assets, msg.sender, msg.sender);
    }

    ////////////////////////// Internal //////////////////////////

    function _poolWithdraw(IERC4626 pool, uint256 assets) internal {
        pool.withdraw(assets, address(this), address(this));
        emit PoolWithdraw(address(pool), assets);
    }

    function _withdrawWithPath(uint256 assets, uint256[] memory path) internal {
        uint256 balance = IERC20(this.asset()).balanceOf(address(this));

        if (balance > assets) {
            return;
        } else {
            // We only want to allow a user to withdraw enough to cover the differnce
            uint256 diff = assets - balance;

            for (uint256 i; i < path.length; i++) {
                if (path[i] > diff) {
                    diff -= path[i];
                    _poolWithdraw(poolCaps.pool(i), path[i]);
                } else {
                    _poolWithdraw(poolCaps.pool(i), diff);
                    break;
                }
            }
        }
    }

    ////////////////////////// Overrides //////////////////////////

    function totalAssets() public view override returns (uint256 total) {
        uint256 len = poolCaps.length();
        for (uint256 i; i < len; i++) {
            IERC4626 pool = IERC4626(poolCaps.pool(i));

            uint256 sharesBalance = pool.balanceOf(address(this));
            total += pool.previewRedeem(sharesBalance);
        }
    }

    function maxDeposit(address) public view override returns (uint256) {
        return totalPoolCap - totalAssets();
    }

    function maxMint(address) public view override returns (uint256) {
        uint256 _maxDeposit = maxDeposit(address(0));
        return previewDeposit(_maxDeposit);
    }

    ////////////////////////// Public //////////////////////////

    function pools() public view returns (IERC4626[] memory) {
        return poolCaps.allPools();
    }

    function poolCap(IERC4626 _pool) public view returns (uint256) {
        return poolCaps.read(_pool);
    }
}
