// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

//types
import {Pool} from "./Pool.sol";
import {IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts-upgradeable/interfaces/IERC4626.sol";
// libraries
import {IterableMap} from "src/lib/IterableMap.sol";
//contracts
import {ERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Ownable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Pausable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC4626} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

contract SuperPool is Ownable, Pausable, ERC4626 {
    using IterableMap for IterableMap.IterableMapStorage;

    /// An internal mapping of Pool => Pool Cap, incldudes an array of pools with non zero cap.
    IterableMap.IterableMapStorage internal poolCaps;

    /// The cumlative deposit cap for all pools
    uint256 public totalPoolCap;

    /// Privileged address allowed to allocate funds to and from pools on behalf of the owner
    address public allocator;

    event PoolCapSet(address indexed pool, uint256 amt);
    event PoolDeposit(address indexed pool, uint256 assets);
    event PoolWithdraw(address indexed pool, uint256 assets);

    error PoolCapTooLow();
    error InvalidPoolAsset();
    error OnlyAllocatorOrOwner();

    constructor(address _asset, string memory _name, string memory _symbol, address owner)
        Ownable(owner)
        ERC20(_name, _symbol)
        ERC4626(IERC20(_asset))
    {}

    ////////////////////////// Only Owner //////////////////////////

    function setPoolCap(address pool, uint256 assets) external onlyOwner {
        if (Pool(pool).asset() != asset()) revert InvalidPoolAsset();
        if (assets == 0 && poolCaps.get(pool) == 0) {
            return; // nothing to do
        }
        if (IERC4626(pool).previewRedeem(IERC4626(pool).balanceOf(address(this))) > assets) {
            revert PoolCapTooLow();
        }
        totalPoolCap = totalPoolCap - poolCaps.get(pool) + assets;
        poolCaps.set(pool, assets);
        emit PoolCapSet(pool, assets);
    }

    function poolDeposit(address pool, uint256 assets) external {
        if (msg.sender != allocator && msg.sender != owner()) revert OnlyAllocatorOrOwner();
        IERC20(asset()).approve(address(pool), assets);
        IERC4626(pool).deposit(assets, address(this));
        require(IERC4626(pool).balanceOf(address(this)) <= poolCap(pool));
        emit PoolDeposit(pool, assets);
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
        uint256 balance = IERC20(asset()).balanceOf(address(this));

        if (balance > assets) {
            return;
        } else {
            // We only want to allow a user to withdraw enough to cover the differnce
            uint256 diff = assets - balance;

            for (uint256 i; i < path.length; i++) {
                if (path[i] > diff) {
                    diff -= path[i];
                    _poolWithdraw(IERC4626(poolCaps.getByIdx(i)), path[i]);
                } else {
                    _poolWithdraw(IERC4626(poolCaps.getByIdx(i)), diff);
                    break;
                }
            }
        }
    }

    ////////////////////////// Overrides //////////////////////////

    function totalAssets() public view override returns (uint256) {
        uint256 len = poolCaps.length();
        uint256 total;
        for (uint256 i; i < len; i++) {
            IERC4626 pool = IERC4626(poolCaps.getByIdx(i));
            total += pool.previewRedeem(pool.balanceOf(address(this)));
        }
        return total;
    }

    function maxDeposit(address) public view override returns (uint256) {
        return totalPoolCap - totalAssets();
    }

    function maxMint(address) public view override returns (uint256) {
        uint256 _maxDeposit = maxDeposit(address(0));
        return previewDeposit(_maxDeposit);
    }

    ////////////////////////// Public //////////////////////////

    function pools() public view returns (address[] memory) {
        return poolCaps.getKeys();
    }

    function poolCap(address _pool) public view returns (uint256) {
        return poolCaps.get(_pool);
    }
}
