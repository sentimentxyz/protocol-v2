// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

//types
import {Pool} from "./Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
// libraries
import {Errors} from "src/lib/Errors.sol";
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

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    // internal iterable mapping of (pool => pool cap)
    IterableMap.IterableMapStorage internal poolCaps;

    // aggregate deposit cap for all pools
    // updated dynamically when individual pool caps are updated
    uint256 public totalPoolCap;

    // protocol fee, collected on withdrawal
    uint256 public protocolFee;

    // privileged address to allocate assets between pools
    address public allocator;

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event PoolCapSet(address indexed pool, uint256 amt);
    event PoolDeposit(address indexed pool, uint256 assets);
    event PoolWithdraw(address indexed pool, uint256 assets);

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address asset, string memory _name, string memory _symbol) public initializer {
        OwnableUpgradeable.__Ownable_init(msg.sender);
        PausableUpgradeable.__Pausable_init();
        ERC20Upgradeable.__ERC20_init(_name, _symbol);
        ERC4626Upgradeable.__ERC4626_init(IERC20(asset));
    }

    /*//////////////////////////////////////////////////////////////
                             Public View
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                        ERC4626 View Overrides
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ERC4626Upgradeable
    function totalAssets() public view override returns (uint256) {
        // fetch number of pools
        uint256 len = poolCaps.length();

        // compute total assets managed by superpool across associated pools
        uint256 total;
        for (uint256 i; i < len; i++) {
            // fetch pool by id
            IERC4626 pool = IERC4626(poolCaps.getByIdx(i));

            // fetch assets owned by superpool in the pool
            total += pool.previewRedeem(pool.balanceOf(address(this)));
        }

        // fetch idle assets held in superpool
        total += IERC20(asset()).balanceOf(address(this));

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

    /*//////////////////////////////////////////////////////////////
                          ERC4626 Overrides
    //////////////////////////////////////////////////////////////*/

    // deposit and mint work as-is, but are pausable

    /// @inheritdoc ERC4626Upgradeable
    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        ERC4626Upgradeable.deposit(assets, receiver);
    }

    /// @inheritdoc ERC4626Upgradeable
    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256) {
        ERC4626Upgradeable.mint(shares, receiver);
    }

    // withdraw and mint have no major changes, but the superpool implements a withdrawal fee
    // the fee is deducted as a portion of the withdrawn assets and accrues to the protocol
    // the return values are recalibrated to comply with the ERC4626 specification
    // withdraw and mint are not pausable so that depositors can withdraw, no matter what

    /// @notice withdraw assets from the superpool
    /// @dev override to account for protocol fee
    /// @param assets the amount of assets to withdraw
    /// @param receiver the address to send the assets to
    /// @param owner the owner of the shares were burning from
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        // compute fee amount for given assets
        uint256 fee = protocolFee.mulDiv(assets, 1e18);

        // erc4626 return val for fee withdrawal
        uint256 feeShares = ERC4626Upgradeable.withdraw(fee, OwnableUpgradeable.owner(), owner);

        // erc4626 return val for receiver shares withdrawal
        uint256 recieverShares = ERC4626Upgradeable.withdraw(assets, receiver, owner);

        // final return value must comply with erc4626 spec
        return feeShares + recieverShares;
    }

    /// @notice redeem shares for assets from the superpool
    /// @dev override to account for protocol fee
    /// @param shares the amount of shares to redeem
    /// @param receiver the address to send the assets to
    /// @param owner the owner of the shares were burning from
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        // compute fee amount for given shares
        uint256 fee = protocolFee.mulDiv(shares, 1e18);

        // erc4626 return val for fee redemption
        uint256 feeAssets = ERC4626Upgradeable.redeem(fee, OwnableUpgradeable.owner(), owner);

        // erc4626 return val for receiver asset redemption
        uint256 receiverAssets = ERC4626Upgradeable.redeem(shares, receiver, owner);

        // final return value must comply with erc4626 spec
        return feeAssets + receiverAssets;
    }

    /// @notice withdraw assets from the superpool using a given path
    /// @dev withdraw assets from the superpool by taking path[i] underlying from the pool at poolCaps[i]
    /// @param assets the amount of assets to withdraw
    /// @param path the amounts to withdraw from each pool
    function withdrawWithPath(uint256 assets, uint256[] memory path) external whenNotPaused {
        // withdraw assets from pool to superpool along given path
        _withdrawWithPath(assets, path);

        // withdraw assets to depositor
        withdraw(assets, msg.sender, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                          Internal Functions
    //////////////////////////////////////////////////////////////*/

    function _poolWithdraw(IERC4626 pool, uint256 assets) internal {
        // withdraw assets from pool back to superpool
        pool.withdraw(assets, address(this), address(this));

        emit PoolWithdraw(address(pool), assets);
    }

    /// @dev returns early if the amount they want to withdraw is already in the superpool
    /// @dev if you try to withdraw more this function will ignore it
    function _withdrawWithPath(uint256 assets, uint256[] memory path) internal {
        // fetch amount of idle funds currently held in pool
        uint256 balance = IERC20(asset()).balanceOf(address(this));

        // no need to withdraw from pools if the superpool has enough to meet the withdrawal
        // TODO refactor if-else
        if (balance > assets) {
            return;
        } else {
            // fetch amount diff that needs to be withdrawn from pools to meet withdrawal
            uint256 diff = assets - balance;

            for (uint256 i; i < path.length; i++) {
                // if we covering the rest of the funds from this last pool
                if (path[i] > diff) {
                    diff -= path[i];
                    _poolWithdraw(IERC4626(poolCaps.getByIdx(i)), path[i]);
                } else {
                    _poolWithdraw(IERC4626(poolCaps.getByIdx(i)), diff);
                    break;
                }
            }

            // TODO revert if diff is still > 0
        }
    }

    /*//////////////////////////////////////////////////////////////
                       Only Allocator and Owner
    //////////////////////////////////////////////////////////////*/

    /// @notice deposit assets from the superpool into a pool
    /// @notice callable only by privilaged allocator or owner
    /// @param pool the pool to deposit assets into
    /// @param assets the amount of assets to deposit
    function poolDeposit(address pool, uint256 assets) external {
        // revert unauthorized calls
        if (msg.sender != allocator && msg.sender != owner()) revert Errors.OnlyAllocatorOrOwner();

        // approve and deposit assets from superpool to given pool
        IERC20(asset()).approve(address(pool), assets);
        IERC4626(pool).deposit(assets, address(this));

        // revert if pool balance
        require(IERC4626(pool).balanceOf(address(this)) <= poolCap(pool));

        emit PoolDeposit(pool, assets);
    }

    /// @notice withdraw assets from a pool
    /// @notice only callable by owner
    /// @param pool the pool to withdraw assets from
    /// @param assets the amount of assets to withdraw
    function poolWithdraw(address pool, uint256 assets) external onlyOwner {
        // revert unauthorized calls
        if (msg.sender != allocator && msg.sender != owner()) revert Errors.OnlyAllocatorOrOwner();
        _poolWithdraw(IERC4626(pool), assets);
    }

    /*//////////////////////////////////////////////////////////////
                              Only Owner
    //////////////////////////////////////////////////////////////*/

    /// @notice set the maximum deposit cap for a pool
    /// @param pool the pool to set the cap for
    /// @param assets the amount of assets to set the cap to
    function setPoolCap(address pool, uint256 assets) external onlyOwner {
        // revert if pool asset does not match superpool asset
        if (Pool(pool).asset() != asset()) revert Errors.InvalidPoolAsset();

        // shortcut no-op path to handle zeroed out params
        if (assets == 0 && poolCaps.get(pool) == 0) {
            return;
        }

        // revert if current superpool holdings are greater than new cap
        if (IERC4626(pool).previewRedeem(IERC4626(pool).balanceOf(address(this))) > assets) {
            revert Errors.PoolCapTooLow();
        }

        // update aggregate pool cap across superpool
        totalPoolCap = totalPoolCap - poolCaps.get(pool) + assets;

        // update pool cap in storage mapping
        poolCaps.set(pool, assets);

        emit PoolCapSet(pool, assets);
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
}
