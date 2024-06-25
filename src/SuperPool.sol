// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            SuperPool
//////////////////////////////////////////////////////////////*/

// types
import { Pool } from "./Pool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

// contracts
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title SuperPool
/// @notice Aggregator of underlying pools compliant with ERC4626
contract SuperPool is Ownable, Pausable, ERC20 {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice The denominator for fixed point number calculations
    uint256 internal constant WAD = 1e18;
    /// @notice The maximum length of the deposit and withdraw queues
    uint256 public constant MAX_QUEUE_LENGTH = 8;

    uint8 internal immutable DECIMALS;
    /// @notice The singleton pool contract associated with this superpool
    Pool public immutable POOL;
    /// @notice The asset that is deposited in the superpool, and in turns its underling pools
    IERC20 internal immutable ASSET;
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

    /// @notice Pool added to the deposit and withdraw queue
    event PoolAdded(uint256 poolId);
    /// @notice Pool removed from the deposit and withdraw queue
    event PoolRemoved(uint256 poolId);
    /// @notice SuperPool fee was updated
    event SuperPoolFeeUpdated(uint256 fee);
    /// @notice Asset cap for an underlying pool was updated
    event PoolCapSet(uint256 poolId, uint256 cap);
    /// @notice SuperPool aggregate deposit asset cap was updated
    event SuperPoolCapUpdated(uint256 superPoolCap);
    /// @notice SuperPool fee recipient was updated
    event SuperPoolFeeRecipientUpdated(address feeRecipient);
    /// @notice Allocator status for a given address was updated
    event AllocatorUpdated(address allocator, bool isAllocator);
    /// @notice Assets were deposited to the SuperPool
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    /// @notice Assets were withdrawn from the SuperPool
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /// @notice Attempt to deposit zero shares worth of assets to the pool
    error SuperPool_ZeroShareDeposit(address superpool, uint256 assets);
    /// @notice Attempt to mint zero asset worth of shares from the pool
    error SuperPool_ZeroAssetDeposit(address superpool, uint256 shares);
    /// @notice Insufficient Liquidity to service withdrawal
    error SuperPool_NotEnoughLiquidity(address superPool);
    /// @notice Reordered queue length does not match current queue length
    error SuperPool_QueueLengthMismatch(address superPool);
    /// @notice Number of pools in the queue exceeds MAX_QUEUE_LENGTH
    error SuperPool_MaxQueueLengthReached(address superPool);
    /// @notice Underlying pool asset does not match Super Pool asset
    error SuperPool_PoolAssetMismatch(address superPool, uint256 poolId);
    /// @notice Attempt to remove underlying pool with non-zero deposits
    error SuperPool_NonZeroPoolBalance(address superPool, uint256 poolId);
    /// @notice Function access is restricted to pool owners and allocators
    error SuperPool_OnlyAllocatorOrOwner(address superPool, address sender);

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
    ) Ownable() ERC20(name_, symbol_) {
        POOL = Pool(pool_);
        ASSET = IERC20(asset_);
        DECIMALS = _tryGetAssetDecimals(ASSET);

        fee = fee_;
        feeRecipient = feeRecipient_;
        superPoolCap = superPoolCap_;
    }

    /// @notice Number of decimals used to get user representation of amounts
    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }

    /// @notice Returns the address of the underlying token
    function asset() public view returns (address) {
        return address(ASSET);
    }

    /// @notice Fetch the total amount of assets under control of the SuperPool
    function totalAssets() public view returns (uint256) {
        uint256 assets = ASSET.balanceOf(address(this));

        uint256 depositQueueLength = depositQueue.length;
        for (uint256 i; i < depositQueueLength; ++i) {
            assets += POOL.getAssetsOf(depositQueue[i], address(this));
        }

        return assets;
    }

    /// @notice Converts an asset amount to a share amount, as defined by ERC4626
    /// @param assets The amount of assets
    /// @return shares The equivalent amount of shares
    function convertToShares(uint256 assets) public view virtual returns (uint256 shares) {
        (uint256 feeShares, uint256 newTotalAssets) = simulateAccrue();
        return _convertToShares(assets, newTotalAssets, totalSupply() + feeShares, Math.Rounding.Down);
    }

    /// @notice Converts a share amount to an asset amount, as defined by ERC4626
    /// @param shares The amount of shares
    /// @return assets The equivalent amount of assets
    function convertToAssets(uint256 shares) public view virtual returns (uint256 assets) {
        (uint256 feeShares, uint256 newTotalAssets) = simulateAccrue();
        return _convertToAssets(shares, newTotalAssets, totalSupply() + feeShares, Math.Rounding.Down);
    }

    /// @notice Fetch the maximum amount of assets that can be deposited in the SuperPool
    function maxDeposit(address) public view returns (uint256) {
        return _maxDeposit(totalAssets());
    }

    /// @notice Fetch the maximum amount of shares that can be minted from the SuperPool
    function maxMint(address) public view returns (uint256) {
        (uint256 feeShares, uint256 newTotalAssets) = simulateAccrue();
        return
            _convertToShares(_maxDeposit(newTotalAssets), newTotalAssets, totalSupply() + feeShares, Math.Rounding.Down);
    }

    /// @notice Fetch the maximum amount of assets that can be withdrawn by a depositor
    function maxWithdraw(address owner) public view returns (uint256) {
        (uint256 feeShares, uint256 newTotalAssets) = simulateAccrue();
        return _maxWithdraw(owner, newTotalAssets, totalSupply() + feeShares);
    }

    /// @notice Fetch the maximum amount of shares that can be redeemed by a depositor
    function maxRedeem(address owner) public view returns (uint256) {
        (uint256 feeShares, uint256 newTotalAssets) = simulateAccrue();
        uint256 newTotalShares = totalSupply() + feeShares;
        return _convertToShares(
            _maxWithdraw(owner, newTotalAssets, newTotalShares), newTotalAssets, newTotalShares, Math.Rounding.Down
        );
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        (uint256 feeShares, uint256 newTotalAssets) = simulateAccrue();
        return _convertToShares(assets, newTotalAssets, totalSupply() + feeShares, Math.Rounding.Down);
    }

    function previewMint(uint256 shares) public view virtual returns (uint256) {
        (uint256 feeShares, uint256 newTotalAssets) = simulateAccrue();
        return _convertToAssets(shares, newTotalAssets, totalSupply() + feeShares, Math.Rounding.Up);
    }

    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        (uint256 feeShares, uint256 newTotalAssets) = simulateAccrue();
        return _convertToShares(assets, newTotalAssets, totalSupply() + feeShares, Math.Rounding.Up);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        (uint256 feeShares, uint256 newTotalAssets) = simulateAccrue();
        return _convertToAssets(shares, newTotalAssets, totalSupply() + feeShares, Math.Rounding.Down);
    }

    /// @notice Deposits assets into the SuperPool
    /// @param assets The amount of assets to deposit
    /// @param receiver The address to receive the shares
    /// @return shares The amount of shares minted
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        accrue();
        shares = previewDeposit(assets);
        if (shares == 0) revert SuperPool_ZeroShareDeposit(address(this), assets);
        _deposit(receiver, assets, shares);
    }

    /// @notice Mints shares into the SuperPool
    /// @param shares The amount of shares to mint
    /// @param receiver The address to receive the shares
    /// @return assets The amount of assets deposited
    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        accrue();
        assets = previewMint(shares);
        if (assets == 0) revert SuperPool_ZeroAssetDeposit(address(this), shares);
        _deposit(receiver, assets, shares);
    }

    /// @notice Withdraws assets from the SuperPool
    /// @param assets The amount of assets to withdraw
    /// @param receiver The address to receive the assets
    /// @param owner The address to withdraw the assets from
    /// @return shares The amount of shares burned
    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        accrue();
        shares = previewWithdraw(assets);
        _withdraw(receiver, owner, assets, shares);
    }

    /// @notice Redeems shares from the SuperPool
    /// @param shares The amount of shares to redeem
    /// @param receiver The address to receive the assets
    /// @param owner The address to redeem the shares from
    /// @return assets The amount of assets redeemed
    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        accrue();
        assets = previewRedeem(shares);
        _withdraw(receiver, owner, assets, shares);
    }

    /// @notice Fetch list of pool ids in the deposit and withdraw queue
    function pools() external view returns (uint256[] memory) {
        return depositQueue;
    }

    /// @notice Fetch number of pools in the deposit and withdraw queue
    function getPoolCount() external view returns (uint256) {
        return depositQueue.length;
    }

    /// @notice Accrue interest and fees for the SuperPool
    function accrue() public {
        (uint256 feeShares, uint256 newTotalAssets) = simulateAccrue();
        if (feeShares != 0) ERC20._mint(feeRecipient, feeShares);
        lastTotalAssets = newTotalAssets;
    }

    /// @notice Modify the maximum amount of assets that can be deposited to an underlying pool
    /// @dev If the cap is set below the assets in the pool, it becomes withdraw-only
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
    /// @param allocator The address to toggle allocator status for
    function toggleAllocator(address allocator) external onlyOwner {
        isAllocator[allocator] = !isAllocator[allocator];
        emit AllocatorUpdated(allocator, isAllocator[allocator]);
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
        uint256 poolId;
        uint256 assets;
    }

    /// @notice Reallocate assets between underlying pools
    /// @param withdraws A list of poolIds, and the amount to withdraw from them
    /// @param deposits A list of poolIds, and the amount to deposit to them
    function reallocate(ReallocateParams[] calldata withdraws, ReallocateParams[] calldata deposits) external {
        if (!isAllocator[msg.sender] && msg.sender != Ownable.owner()) {
            revert SuperPool_OnlyAllocatorOrOwner(address(this), msg.sender);
        }

        uint256 withdrawsLength = withdraws.length;
        for (uint256 i; i < withdrawsLength; ++i) {
            POOL.redeem(withdraws[i].poolId, withdraws[i].assets, address(this), address(this));
        }

        uint256 depositsLength = deposits.length;
        for (uint256 i; i < depositsLength; ++i) {
            ASSET.approve(address(POOL), deposits[i].assets);
            POOL.deposit(deposits[i].poolId, deposits[i].assets, address(this));
        }
    }

    /*//////////////////////////////////////////////////////////////
                               Internal
    //////////////////////////////////////////////////////////////*/

    function _convertToShares(
        uint256 _assets,
        uint256 _totalAssets,
        uint256 _totalShares,
        Math.Rounding _rounding
    ) public view virtual returns (uint256 shares) {
        shares = _assets.mulDiv(_totalShares + 1, _totalAssets + 1, _rounding);
    }

    function _convertToAssets(
        uint256 _shares,
        uint256 _totalAssets,
        uint256 _totalShares,
        Math.Rounding _rounding
    ) public view virtual returns (uint256 assets) {
        assets = _shares.mulDiv(_totalAssets + 1, _totalShares + 1, _rounding);
    }

    function _maxWithdraw(address _owner, uint256 _totalAssets, uint256 _totalShares) internal view returns (uint256) {
        uint256 totalLiquidity; // max assets that can be withdrawn based on superpool and underlying pool liquidity
        uint256 depositQueueLength = depositQueue.length;
        for (uint256 i; i < depositQueueLength; ++i) {
            totalLiquidity += POOL.getLiquidityOf(depositQueue[i]);
        }
        totalLiquidity += ASSET.balanceOf(address(this)); // unallocated assets in the superpool

        // return the minimum of totalLiquidity and _owner balance
        uint256 userAssets = _convertToAssets(ERC20.balanceOf(_owner), _totalAssets, _totalShares, Math.Rounding.Down);
        return totalLiquidity > userAssets ? userAssets : totalLiquidity;
    }

    /// @notice Fetch the maximum amount of assets that can be deposited in the SuperPool
    function _maxDeposit(uint256 _totalAssets) public view returns (uint256) {
        return superPoolCap > _totalAssets ? (superPoolCap - _totalAssets) : 0;
    }

    /// @dev Internal function to process ERC4626 deposits and mints
    /// @param receiver The address to receive the shares
    /// @param assets The amount of assets to deposit
    /// @param shares The amount of shares to mint, should be equivalent to assets

    function _deposit(address receiver, uint256 assets, uint256 shares) internal {
        // Need to transfer before minting or ERC777s could reenter.
        ASSET.safeTransferFrom(msg.sender, address(this), assets);
        ERC20._mint(receiver, shares);
        _supplyToPools(assets);
        lastTotalAssets += assets;
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @dev Internal function to process ERC4626 withdrawals and redemptions
    /// @param receiver The address to receive the assets
    /// @param owner The address to withdraw the assets from
    /// @param assets The amount of assets to withdraw
    /// @param shares The amount of shares to burn, should be equivalent to assets
    function _withdraw(address receiver, address owner, uint256 assets, uint256 shares) internal {
        _withdrawFromPools(assets);
        if (msg.sender != owner) ERC20._spendAllowance(owner, msg.sender, shares);
        ERC20._burn(owner, shares);
        ASSET.safeTransfer(receiver, assets);
        lastTotalAssets -= assets;
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /// @dev Internal function to loop through all pools, depositing assets sequentially until the cap is reached
    /// @param assets The amount of assets to deposit
    function _supplyToPools(uint256 assets) internal {
        uint256 depositQueueLength = depositQueue.length;
        for (uint256 i; i < depositQueueLength; ++i) {
            uint256 poolId = depositQueue[i];
            uint256 assetsInPool = POOL.getAssetsOf(poolId, address(this));

            if (assetsInPool < poolCap[poolId]) {
                uint256 supplyAmt = poolCap[poolId] - assetsInPool;
                if (assets < supplyAmt) supplyAmt = assets;
                ASSET.forceApprove(address(POOL), supplyAmt);

                POOL.deposit(poolId, supplyAmt, address(this));
                assets -= supplyAmt;

                if (assets == 0) return;
            }
        }
    }

    /// @dev Internal function to loop through all pools, withdrawing assets first from available balance
    ///     then sequentially until the cap is reached
    /// @param assets The amount of assets to withdraw
    function _withdrawFromPools(uint256 assets) internal {
        uint256 assetsInSuperpool = ASSET.balanceOf(address(this));

        if (assetsInSuperpool >= assets) return;
        else assets -= assetsInSuperpool;

        uint256 withdrawQueueLength = withdrawQueue.length;
        for (uint256 i; i < withdrawQueueLength; ++i) {
            uint256 poolId = withdrawQueue[i];
            uint256 assetsInPool = POOL.getAssetsOf(poolId, address(this));

            if (assetsInPool > 0) {
                uint256 withdrawAmt = (assetsInPool < assets) ? assetsInPool : assets;

                if (withdrawAmt > 0) {
                    try POOL.redeem(poolId, withdrawAmt, address(this), address(this)) {
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
        if (POOL.getPoolAssetFor(poolId) != address(ASSET)) revert SuperPool_PoolAssetMismatch(address(this), poolId);
        if (depositQueue.length == MAX_QUEUE_LENGTH) revert SuperPool_MaxQueueLengthReached(address(this));

        depositQueue.push(poolId);
        withdrawQueue.push(poolId);
    }

    /// @dev Internal function to remove a pool from the SuperPool
    /// @param poolId The id of the pool to remove, cannot be removed if the pool has non-zero balance
    function _removePool(uint256 poolId) internal onlyOwner {
        if (POOL.getAssetsOf(poolId, address(this)) != 0) revert SuperPool_NonZeroPoolBalance(address(this), poolId);

        // gas intensive ops that shift the entire array to preserve order
        _removeFromQueue(depositQueue, poolId);
        _removeFromQueue(withdrawQueue, poolId);

        emit PoolRemoved(poolId);
    }

    /// @dev Internal function to copy a queue to memory from storage
    /// @param queue The queue to copy
    /// @param indexes The new order of the queue
    /// @return newQueue A memory copy of the new queue
    function _reorderQueue(
        uint256[] storage queue,
        uint256[] calldata indexes
    ) internal view returns (uint256[] memory newQueue) {
        uint256 indexesLength = indexes.length;
        newQueue = new uint256[](indexesLength);

        for (uint256 i; i < indexesLength; ++i) {
            newQueue[i] = queue[i];
        }

        return newQueue;
    }

    /// @dev Internal function to remove a pool from a queue
    /// @param queue The queue to remove the pool from
    /// @param poolId The id of the pool to remove
    function _removeFromQueue(uint256[] storage queue, uint256 poolId) internal {
        uint256 toRemoveIdx;
        uint256 queueLength = queue.length;
        for (uint256 i; i < queueLength; ++i) {
            if (queue[i] == poolId) {
                toRemoveIdx = i;
                break;
            }
        }
        for (uint256 i = toRemoveIdx; i < queueLength - 1; ++i) {
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
        uint256 feeShares = _convertToShares(feeAssets, newTotalAssets, totalSupply(), Math.Rounding.Down);

        return (feeShares, newTotalAssets);
    }

    function _tryGetAssetDecimals(IERC20 _asset) private view returns (uint8) {
        (bool success, bytes memory encodedDecimals) =
            address(_asset).staticcall(abi.encodeWithSelector(IERC20Metadata.decimals.selector));
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) return uint8(returnedDecimals);
        }
        return 18;
    }
}
