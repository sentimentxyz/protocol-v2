// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import { Pool } from "./Pool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
// libraries
import { IterableSet } from "./lib/IterableSet.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// contracts
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";

/// @title SuperPool
/// @notice Aggregator of underlying pools compliant with ERC4626
contract SuperPool is Ownable, Pausable, ERC20 {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    /// @notice The denominator for fixed point number calculations
    uint256 constant WAD = 1e18;
    /// @notice The maximum length of the deposit and withdraw queues
    uint256 public constant MAX_QUEUE_LENGTH = 8;
    /// @notice The singleton pool contract associated with this superpool
    Pool public immutable pool;
    /// @notice The asset that is deposited in the superpool, and in turns its underling pools
    IERC20 public asset;
    /// @notice The fee, out of 1e18, taken from interest earned
    uint256 public fee;
    /// @notice The address that recieves all fees, taken in shares
    address public feeRecipient;
    /// @notice The maximum amount of assets that can be deposited in the SuperPool
    uint256 public superPoolCap;
    /// @notice The total amount of assets in the SuperPool
    uint256 public lastTotalAssets;
    /// @notice The queue of pool ids, in order, for depositing assets
    uint256[] public depositQueue;
    /// @notice The queue of pool ids, in order, for withdrawing assets
    uint256[] public withdrawQueue;
    /// @notice The caps of the pools, indexed by pool id
    mapping(uint256 poolId => uint256 cap) public poolCap;
    /// @notice The addresses that are allowed to reallocate assets
    mapping(address user => bool isAllocator) public isAllocator;

    /*//////////////////////////////////////////////////////////////
                                Event
    //////////////////////////////////////////////////////////////*/
    event PoolAdded(uint256 poolId);
    event PoolRemoved(uint256 poolId);
    event SuperPoolFeeUpdated(uint256 fee);
    event PoolCapSet(uint256 poolId, uint256 cap);
    event SuperPoolCapUpdated(uint256 superPoolCap);
    event SuperPoolFeeRecipientUpdated(address feeRecipient);
    event AllocatorUpdated(address allocator, bool isAllocator);
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    /*//////////////////////////////////////////////////////////////
                                Error
    //////////////////////////////////////////////////////////////*/

    error SuperPool_InvalidQueue(address superPool);
    error SuperPool_AllCapsReached(address superPool);
    error SuperPool_ZeroShareDeposit(address superpool);
    error SuperPool_ZeroAssetDeposit(address superpool);
    error SuperPool_NotEnoughLiquidity(address superPool);
    error SuperPool_QueueLengthMismatch(address superPool);
    error SuperPool_MaxQueueLengthReached(address superPool);
    error SuperPool_PoolAssetMismatch(address superPool, uint256 poolId);
    error SuperPool_NonZeroPoolBalance(address superPool, uint256 poolId);
    error SuperPool_OnlyAllocatorOrOwner(address superPool, address sender);

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    /// @notice This function should only be called by the SuperPool Factory
    /// @param pool_ The address of the singelton pool contract
    /// @param asset_ The asset of the superpool, which should match all underling pools
    /// @param feeRecipient_ The address to initially receive the fee
    /// @param fee_ The fee, out of 1e18, taken from interest earned
    /// @param superPoolCap_ The maximum amount of assets that can be deposited in the SuperPool
    /// @param name_ The name of the SuperPool
    /// @param symbol_ The symbol of the SuperPool
    constructor(
        address pool_,
        address asset_,
        address feeRecipient_,
        uint256 fee_,
        uint256 superPoolCap_,
        string memory name_,
        string memory symbol_
    )
        Ownable()
        ERC20(name_, symbol_)
    {
        asset = IERC20(asset_);
        pool = Pool(pool_);

        fee = fee_;
        feeRecipient = feeRecipient_;
        superPoolCap = superPoolCap_;
    }

    /*//////////////////////////////////////////////////////////////
                               External
    //////////////////////////////////////////////////////////////*/

    /// @return The pool ids in the deposit queue
    function pools() external view returns (uint256[] memory) {
        return depositQueue;
    }

    /// @return The number of pools where assets are being lent out
    function getPoolCount() external view returns (uint256) {
        return depositQueue.length;
    }

    /*//////////////////////////////////////////////////////////////
                                Public
    //////////////////////////////////////////////////////////////*/

    /// @notice Accrues interest and fees for the SuperPool
    function accrue() public {
        (uint256 feeShares, uint256 newTotalAssets) = simulateAccrue();
        if (feeShares != 0) ERC20._mint(feeRecipient, feeShares);
        lastTotalAssets = newTotalAssets;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 View Overrides
    //////////////////////////////////////////////////////////////*/

    /// @return _totalAssets The total amount of assets under control of the SuperPool
    function totalAssets() public view returns (uint256 _totalAssets) {
        uint256 assets = IERC20(asset).balanceOf(address(this));

        for (uint256 i; i < depositQueue.length; ++i) {
            assets += pool.getAssetsOf(depositQueue[i], address(this));
        }

        _totalAssets = assets;
    }

    /// @return assets maxDeposit The maximum amount of assets that can be deposited in the SuperPool
    function maxDeposit(address) public view returns (uint256 assets) {
        uint256 _totalAssets = totalAssets();
        return superPoolCap > _totalAssets ? (superPoolCap - _totalAssets) : 0;
    }

    /// @return shares The maximum amount of shares that can be minted from the SuperPool
    function maxMint(address) public view returns (uint256 shares) {
        return convertToShares(maxDeposit(address(0)));
    }

    /// @param owner The address to check the maximum withdraw amount for
    /// @return assets The maximum amount of assets that can be withdrawn from the SuperPool
    function maxWithdraw(address owner) public view returns (uint256 assets) {
        uint256 totalLiquidity;
        for (uint256 i; i < depositQueue.length; ++i) {
            totalLiquidity += pool.getLiquidityOf(depositQueue[i]);
        }

        totalLiquidity += asset.balanceOf(address(this));

        uint256 userAssets = convertToAssets(ERC20.balanceOf(owner));

        return totalLiquidity > userAssets ? userAssets : totalLiquidity;
    }

    /// @param owner The address to check the maximum redeem amount for
    /// @return shares The maximum amount of shares that can be redeemed from the SuperPool
    function maxRedeem(address owner) public view returns (uint256 shares) {
        return convertToShares(maxWithdraw(owner));
    }

    /*//////////////////////////////////////////////////////////////
                          ERC4626 Overrides
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits assets into the SuperPool
    /// @param assets The amount of assets to deposit
    /// @param receiver The address to receive the shares
    /// @return shares The amount of shares minted
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        accrue();
        shares = convertToShares(assets);
        if (shares == 0) revert SuperPool_ZeroShareDeposit(address(this));
        _deposit(receiver, assets, shares);
    }

    /// @notice Mints shares into the SuperPool
    /// @param shares The amount of shares to mint
    /// @param receiver The address to receive the shares
    /// @return assets The amount of assets deposited
    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        accrue();
        assets = convertToAssets(shares);
        if (assets == 0) revert SuperPool_ZeroAssetDeposit(address(this));
        _deposit(receiver, assets, shares);
    }

    /// @notice Withdraws assets from the SuperPool
    /// @param assets The amount of assets to withdraw
    /// @param receiver The address to receive the assets
    /// @param owner The address to withdraw the assets from
    /// @return shares The amount of shares burned
    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        accrue();
        shares = convertToShares(assets);
        _withdraw(receiver, owner, assets, shares);
    }

    /// @notice Redeems shares from the SuperPool
    /// @param shares The amount of shares to redeem
    /// @param receiver The address to receive the assets
    /// @param owner The address to redeem the shares from
    /// @return assets The amount of assets redeemed
    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        accrue();
        assets = convertToAssets(shares);
        _withdraw(receiver, owner, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                              Only Owner
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the cap of a pool
    /// @notice If the cap is set below the assets in the pool, it becomes withdraw-only
    /// @param poolId The id of the pool to set the cap for
    /// @param cap The cap of the pool, 0 to remove the cap
    function setPoolCap(uint256 poolId, uint256 cap) external onlyOwner {
        // add new pool
        if (poolCap[poolId] == 0 && cap != 0) {
            _addPool(poolId);
            poolCap[poolId] = cap;
        }
        // remove existing pool
        else if (poolCap[poolId] != 0 && cap == 0) {
            _removePool(poolId);
            poolCap[poolId] = 0;
        } else if (poolCap[poolId] != 0 && cap != 0) {
            poolCap[poolId] = cap;
        } else {
            return; // handle pool == 0 && cap == 0
        }

        emit PoolCapSet(poolId, cap);
    }

    /// @notice Reorders the deposit queue, based in deposit priority
    /// @param indexes The new depositQueue, in order of priority
    function reorderDepositQueue(uint256[] calldata indexes) external onlyOwner {
        if (indexes.length != depositQueue.length) revert SuperPool_QueueLengthMismatch(address(this));
        depositQueue = _reorderQueue(depositQueue, indexes);
    }

    /// @notice Reorders the withdraw queue, based in withdraw priority
    /// @param indexes The new withdrawQueue, in order of priority
    function reorderWithdrawQueue(uint256[] calldata indexes) external onlyOwner {
        if (indexes.length != withdrawQueue.length) revert SuperPool_QueueLengthMismatch(address(this));
        withdrawQueue = _reorderQueue(withdrawQueue, indexes);
    }

    /// @notice Toggles whether or not an address is able to call reallocate
    /// @param _allocator The address to toggle for
    function toggleAllocator(address _allocator) external onlyOwner {
        isAllocator[_allocator] = !isAllocator[_allocator];

        emit AllocatorUpdated(_allocator, isAllocator[_allocator]);
    }

    /// @notice Sets the fee for the SuperPool
    /// @param _fee The fee, out of 1e18, to be taken from interest earned
    function setFee(uint256 _fee) external onlyOwner {
        accrue();

        fee = _fee;

        emit SuperPoolFeeUpdated(_fee);
    }

    /// @notice Sets the cap of the total amount of assets in the SuperPool
    /// @param _superPoolCap The cap of the SuperPool
    function setSuperpoolCap(uint256 _superPoolCap) external onlyOwner {
        superPoolCap = _superPoolCap;

        emit SuperPoolCapUpdated(_superPoolCap);
    }

    /// @notice Sets the address which fees are sent to
    /// @param _feeRecipient The new address to recieve fees
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        accrue();

        feeRecipient = _feeRecipient;

        emit SuperPoolFeeRecipientUpdated(_feeRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                           Asset Allocation
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct to hold a pair of pool id, and the delta in balance
    /// @custom:field pool     The pool id
    /// @custom:field assets   The amount of tokens to {deposit, remove} during reallocation
    struct ReallocateParams {
        uint256 pool;
        uint256 assets;
    }

    /// @notice Reallocates assets between pools
    /// @param withdraws A list of poolIds, and the amount to withdraw from them
    /// @param deposits A list of poolIds, and the amount to deposit to them
    function reallocate(ReallocateParams[] calldata withdraws, ReallocateParams[] calldata deposits) external {
        if (!isAllocator[msg.sender] && msg.sender != Ownable.owner()) {
            revert SuperPool_OnlyAllocatorOrOwner(address(this), msg.sender);
        }

        for (uint256 i; i < withdraws.length; ++i) {
            pool.redeem(withdraws[i].pool, withdraws[i].assets, address(this), address(this));
        }

        for (uint256 i; i < deposits.length; ++i) {
            IERC20(asset).approve(address(pool), deposits[i].assets);
            pool.deposit(deposits[i].pool, deposits[i].assets, address(this));
        }
    }

    /// @notice Converts an asset amount to a share amount, as defined by ERC4626
    /// @param assets The amount of assets
    /// @return shares The equivalent amount of shares
    function convertToShares(uint256 assets) public view virtual returns (uint256 shares) {
        uint256 supply = ERC20.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        shares = supply == 0 ? assets : assets.mulDiv(supply, lastTotalAssets, Math.Rounding.Down);
    }

    /// @notice Converts a share amount to an asset amount, as defined by ERC4626
    /// @param shares The amount of shares
    /// @return assets The equivalent amount of assets
    function convertToAssets(uint256 shares) public view virtual returns (uint256 assets) {
        uint256 supply = ERC20.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        assets = supply == 0 ? shares : shares.mulDiv(lastTotalAssets, supply, Math.Rounding.Down);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = ERC20.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDiv(lastTotalAssets, supply, Math.Rounding.Up);
    }

    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = ERC20.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDiv(supply, lastTotalAssets, Math.Rounding.Up);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return convertToAssets(shares);
    }

    /*//////////////////////////////////////////////////////////////
                               Internal
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits assets into the SuperPool
    /// @param receiver The address to receive the shares
    /// @param assets The amount of assets to deposit
    /// @param shares The amount of shares to mint, should be equivalent to assets
    function _deposit(address receiver, uint256 assets, uint256 shares) internal {
        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        ERC20._mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        _supplyToPools(assets);

        lastTotalAssets += assets;
    }

    /// @notice Withdraws assets from the SuperPool
    /// @param receiver The address to receive the assets
    /// @param owner The address to withdraw the assets from
    /// @param assets The amount of assets to withdraw
    /// @param shares The amount of shares to burn, should be equivalent to assets
    function _withdraw(address receiver, address owner, uint256 assets, uint256 shares) internal {
        _withdrawFromPools(assets);

        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = ERC20.allowance(owner, msg.sender); // Saves gas for limited approvals.

            if (allowed != type(uint256).max) ERC20._spendAllowance(owner, msg.sender, shares);
        }

        ERC20._burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);

        lastTotalAssets -= assets;
    }

    /// @dev Internal function to loop through all pools, depositing assets sequentially until the cap is reached
    /// @param assets The amount of assets to deposit
    function _supplyToPools(uint256 assets) internal {
        for (uint256 i; i < depositQueue.length; ++i) {
            uint256 poolId = depositQueue[i];
            uint256 assetsInPool = pool.getAssetsOf(poolId, address(this));

            if (assetsInPool < poolCap[poolId]) {
                uint256 supplyAmt = poolCap[poolId] - assetsInPool;
                if (assets < supplyAmt) supplyAmt = assets;
                IERC20(asset).forceApprove(address(pool), supplyAmt);

                pool.deposit(poolId, supplyAmt, address(this));
                assets -= supplyAmt;

                if (assets == 0) return;
            }
        }
    }

    /// @dev Internal function to loop through all pools, withdrawing assets first from available balance
    ///     then sequentially until the cap is reached
    /// @param assets The amount of assets to withdraw
    function _withdrawFromPools(uint256 assets) internal {
        uint256 assetsInSuperpool = IERC20(address(asset)).balanceOf(address(this));

        if (assetsInSuperpool >= assets) return;
        else assets -= assetsInSuperpool;

        for (uint256 i; i < withdrawQueue.length; ++i) {
            uint256 poolId = withdrawQueue[i];
            uint256 assetsInPool = pool.getAssetsOf(poolId, address(this));

            if (assetsInPool > 0) {
                uint256 withdrawAmt = (assetsInPool < assets) ? assetsInPool : assets;

                if (withdrawAmt > 0) {
                    // TODO replace with withdraw logic
                    try pool.redeem(poolId, withdrawAmt, address(this), address(this)) {
                        assets -= withdrawAmt;
                    } catch { }
                }

                if (assets == 0) return;
            }
        }

        // We explicitly check assets == 0, and if so return, otherwise we revert directly here
        revert SuperPool_NotEnoughLiquidity(address(this));
    }

    /// @dev Internal function to add a pool to the SuperPool
    /// @param poolId The id of the pool to add
    function _addPool(uint256 poolId) internal {
        if (pool.getPoolAssetFor(poolId) != address(asset)) revert SuperPool_PoolAssetMismatch(address(this), poolId);
        if (depositQueue.length == MAX_QUEUE_LENGTH) revert SuperPool_MaxQueueLengthReached(address(this));

        depositQueue.push(poolId);
        withdrawQueue.push(poolId);
    }

    /// @dev Internal function to remove a pool from the SuperPool
    /// @param poolId The id of the pool to remove, cannot be removed if the pool has non-zero balance
    function _removePool(uint256 poolId) internal onlyOwner {
        if (pool.getAssetsOf(poolId, address(this)) != 0) revert SuperPool_NonZeroPoolBalance(address(this), poolId);

        // gas intensive ops that shift the entire array to preserve order
        _removeFromQueue(depositQueue, poolId);
        _removeFromQueue(withdrawQueue, poolId);

        emit PoolRemoved(poolId);
    }

    /// @dev Internal function to copy a queue to memory from storage
    /// @param queue The queue to copy
    /// @param indexes The new order of the queue
    /// @return newQueue A memory copy of the new queue
    function _reorderQueue(uint256[] storage queue, uint256[] calldata indexes) internal view returns (uint256[] memory newQueue) {
        newQueue = new uint256[](indexes.length);

        for (uint256 i; i < indexes.length; ++i) {
            newQueue[i] = queue[i];
        }

        return newQueue;
    }

    /// @dev Internal function to remove a pool from a queue
    /// @param queue The queue to remove the pool from
    /// @param poolId The id of the pool to remove
    function _removeFromQueue(uint256[] storage queue, uint256 poolId) internal {
        uint256 toRemoveIdx;
        for (uint256 i; i < queue.length; ++i) {
            if (queue[i] == poolId) {
                toRemoveIdx = i;
                break;
            }
        }
        for (uint256 i = toRemoveIdx; i < queue.length - 1; ++i) {
            queue[i] = queue[i + 1];
        }
        queue.pop();
    }

    /// @dev Internal function to simulate the accrual of fees
    /// @return (feeShares, newTotalAssets) The amount of shares accrued and the new total assets
    function simulateAccrue() internal view returns (uint256, uint256) {
        uint256 newTotalAssets = totalAssets();
        uint256 interestAccrued = (newTotalAssets > lastTotalAssets) ? newTotalAssets - lastTotalAssets : 0;
        if (interestAccrued == 0 || fee == 0) return (0, newTotalAssets);

        uint256 feeAssets = interestAccrued.mulDiv(fee, WAD);
        uint256 feeShares = convertToShares(feeAssets);

        return (feeShares, newTotalAssets);
    }
}
