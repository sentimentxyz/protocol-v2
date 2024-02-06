// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

//types
import {Pool} from "./Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
// libraries
import {IterableMap} from "src/lib/IterableMap.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
//contracts
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

contract SuperPool is OwnableUpgradeable, PausableUpgradeable, ERC4626Upgradeable {
    using Math for uint256;
    using IterableMap for IterableMap.IterableMapStorage;

    /// An internal mapping of Pool => Pool Cap, incldudes an array of pools with non zero cap.
    IterableMap.IterableMapStorage internal poolCaps;

    /// The cumlative deposit cap for all pools
    uint256 public totalPoolCap;

    uint256 public protocolFee; // protocol fee
    address public allocator; // priveilaged address to allocate assets between pools

    event PoolCapSet(address indexed pool, uint256 amt);
    event PoolDeposit(address indexed pool, uint256 assets);
    event PoolWithdraw(address indexed pool, uint256 assets);

    error PoolCapTooLow();
    error InvalidPoolAsset();
    error OnlyAllocatorOrOwner();

    constructor() {
        _disableInitializers();
    }

    function initialize(address asset, string memory _name, string memory _symbol) public initializer {
        OwnableUpgradeable.__Ownable_init(msg.sender);
        PausableUpgradeable.__Pausable_init();
        ERC20Upgradeable.__ERC20_init(_name, _symbol);
        ERC4626Upgradeable.__ERC4626_init(IERC20(asset));
    }

    ////////////////////////// Only Owner //////////////////////////

    /// @notice set the maximum deposit cap for a pool
    /// @param pool the pool to set the cap for
    /// @param assets the amount of assets to set the cap to
    /// @dev checks if pool.asset() == this.asset()
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

    /// @notice deposit assets into a pool
    /// @notice callable by privilaged allocator or owner
    /// @param pool the pool to deposit assets into
    /// @param assets the amount of assets to deposit
    function poolDeposit(address pool, uint256 assets) external {
        if (msg.sender != allocator && msg.sender != owner()) revert OnlyAllocatorOrOwner();
        IERC20(asset()).approve(address(pool), assets);
        IERC4626(pool).deposit(assets, address(this));
        require(IERC4626(pool).balanceOf(address(this)) <= poolCap(pool));
        emit PoolDeposit(pool, assets);
    }
    
    /// @notice withdraw assets from a pool
    /// @notice only callable by owner
    /// @param pool the pool to withdraw assets from
    /// @param assets the amount of assets to withdraw
    function poolWithdraw(address pool, uint256 assets) external onlyOwner {
        _poolWithdraw(IERC4626(pool), assets);
    }

    /// @notice set the allocator address
    /// @param _allocator the address to set the allocator to
    function setAllocator(address _allocator) external onlyOwner {
        allocator = _allocator;
    }

    /// @notice set the protocol fee
    /// @param _protocolFee the fee to set
    function setProtocolFee(uint256 _protocolFee) external onlyOwner {
        protocolFee = _protocolFee;
    }

    ////////////////////////// Withdraw //////////////////////////

    /// @notice withdraw assets from the superpool
    /// @dev override to account for protocol fee
    /// @param assets the amount of assets to withdraw
    /// @param receiver the address to send the assets to
    /// @param owner the owner of the shares were burning from
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        uint256 fee = protocolFee.mulDiv(assets, 1e18);
        uint256 feeShares = ERC4626Upgradeable.withdraw(fee, OwnableUpgradeable.owner(), owner);
        uint256 recieverShares = ERC4626Upgradeable.withdraw(assets, receiver, owner);
        return feeShares + recieverShares;
    }

    /// @notice redeem shares for assets from the superpool
    /// @dev override to account for protocol fee
    /// @param shares the amount of shares to redeem
    /// @param receiver the address to send the assets to
    /// @param owner the owner of the shares were burning from
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        uint256 fee = protocolFee.mulDiv(shares, 1e18);
        uint256 feeAssets = ERC4626Upgradeable.redeem(fee, OwnableUpgradeable.owner(), owner);
        uint256 receiverAssets = ERC4626Upgradeable.redeem(shares, receiver, owner);
        return feeAssets + receiverAssets;
    }

    /// @notice withdraw assets from the superpool using a path
    /// @dev withdraw assets from the superpool by taking path[i] underlying from the pool at poolCaps[i]
    /// @param assets the amount of assets to withdraw
    /// @param path the amounts to withdraw from each pool
    function withdrawWithPath(uint256 assets, uint256[] memory path) external whenNotPaused {
        _withdrawWithPath(assets, path);
        withdraw(assets, msg.sender, msg.sender);
    }

    ////////////////////////// Internal //////////////////////////

    function _poolWithdraw(IERC4626 pool, uint256 assets) internal {
        pool.withdraw(assets, address(this), address(this));
        emit PoolWithdraw(address(pool), assets);
    }

    /// @dev returns early if the amount they want to withdraw is already in the superpool
    /// @dev if you try to withdraw more this function will ignore it
    function _withdrawWithPath(uint256 assets, uint256[] memory path) internal {
        uint256 balance = IERC20(asset()).balanceOf(address(this));

        if (balance > assets) {
            return;
        } else {
            // We only want to allow a user to withdraw enough to cover the differnce
            uint256 diff = assets - balance;

            for (uint256 i; i < path.length; i++) {
                // if the amount were withdrawing from this pool is less than the current amount we need to withdrawl
                if (path[i] < diff) {
                    diff -= path[i];
                    _poolWithdraw(IERC4626(poolCaps.getByIdx(i)), path[i]);
                } else {
                    // else this is the last iteration and we need to withdraw the remaining amount
                    _poolWithdraw(IERC4626(poolCaps.getByIdx(i)), diff);
                    break;
                }
            }
        }
    }

    ////////////////////////// Overrides //////////////////////////

    /// @inheritdoc ERC4626Upgradeable
    function totalAssets() public view override returns (uint256) {
        uint256 len = poolCaps.length();
        uint256 total;
        for (uint256 i; i < len; i++) {
            IERC4626 pool = IERC4626(poolCaps.getByIdx(i));
            total += pool.previewRedeem(pool.balanceOf(address(this)));
            total += IERC20(pool.asset()).balanceOf(address(this));
        }
        return total;
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxDeposit(address) public view override returns (uint256) {
        return totalPoolCap - totalAssets();
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxMint(address) public view override returns (uint256) {
        return previewDeposit(maxDeposit(address(0)));
    }

    ////////////////////////// Public //////////////////////////

    /// @notice returns the pools with non zero deposit caps
    /// @return an array of pool addresses
    function pools() public view returns (address[] memory) {
        return poolCaps.getKeys();
    }

    /// @notice returns the deposit cap for a give pool
    /// @param _pool the pool to get the cap for
    function poolCap(address _pool) public view returns (uint256) {
        return poolCaps.get(_pool);
    }
}
