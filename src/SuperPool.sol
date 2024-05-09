// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {Pool} from "./Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
// libraries
import {IterableSet} from "./lib/IterableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
//contracts
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

// inspired by yearn v3 and metamorpho vaults
contract SuperPool is OwnableUpgradeable, PausableUpgradeable, ERC4626Upgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    uint256 constant WAD = 1e18;
    uint256 public constant MAX_QUEUE_LENGTH = 8;

    Pool public pool;

    uint256 public fee;
    address public feeRecipient;

    uint256 public superPoolCap;
    uint256 public lastTotalAssets;

    uint256[] public depositQueue;
    uint256[] public withdrawQueue;
    mapping(uint256 poolId => uint256 cap) public poolCap;

    mapping(address => bool) isAllocator;

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

    /*//////////////////////////////////////////////////////////////
                                Error
    //////////////////////////////////////////////////////////////*/

    error SuperPool_InvalidQueue(address superPool);
    error SuperPool_AllCapsReached(address superPool);
    error SuperPool_ZeroShareDeposit(address superpool);
    error SuperPool_NotEnoughLiquidity(address superPool);
    error SuperPool_QueueLengthMismatch(address superPool);
    error SuperPool_MaxQueueLengthReached(address superPool);
    error SuperPool_PoolAssetMismatch(address superPool, uint256 poolId);
    error SuperPool_NonZeroPoolBalance(address superPool, uint256 poolId);
    error SuperPool_OnlyAllocatorOrOwner(address superPool, address sender);

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address asset_,
        address feeRecipient_,
        uint256 fee_,
        uint256 superPoolCap_,
        string memory name_,
        string memory symbol_
    ) public initializer {
        OwnableUpgradeable.__Ownable_init(msg.sender);
        PausableUpgradeable.__Pausable_init();
        ERC20Upgradeable.__ERC20_init(name_, symbol_);
        ERC4626Upgradeable.__ERC4626_init(IERC20(asset_));

        fee = fee_;
        feeRecipient = feeRecipient_;
        superPoolCap = superPoolCap_;
    }

    /*//////////////////////////////////////////////////////////////
                               External
    //////////////////////////////////////////////////////////////*/

    function pools() external view returns (uint256[] memory) {
        return depositQueue;
    }

    function getPoolCount() external view returns (uint256) {
        return depositQueue.length;
    }

    /*//////////////////////////////////////////////////////////////
                                Public
    //////////////////////////////////////////////////////////////*/

    function accrueInterestAndFees() public {
        (uint256 feeShares, uint256 newTotalAssets) = _simulateFeeAccrual();
        if (feeShares != 0) ERC20Upgradeable._mint(feeRecipient, feeShares);
        lastTotalAssets = newTotalAssets;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 View Overrides
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view override returns (uint256) {
        uint256 assets = IERC20(ERC4626Upgradeable.asset()).balanceOf(address(this));

        for (uint256 i; i < depositQueue.length; ++i) {
            assets += pool.getAssetsOf(depositQueue[i], address(this));
        }

        return assets;
    }

    function maxDeposit(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        return superPoolCap > assets ? (superPoolCap - assets) : 0;
    }

    function maxMint(address) public view override returns (uint256) {
        return _convertToShares(maxDeposit(address(0)), Math.Rounding.Floor);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        (uint256 assets,,) = _maxWithdraw(owner);
        return assets;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        (uint256 assets, uint256 newTotalSupply, uint256 newTotalAssets) = _maxWithdraw(owner);

        return _convertToSharesWithTotals(assets, newTotalSupply, newTotalAssets, Math.Rounding.Floor);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC4626 Overrides
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        accrueInterestAndFees();
        uint256 shares = _convertToSharesWithTotals(assets, totalSupply(), lastTotalAssets, Math.Rounding.Floor);
        _deposit(msg.sender, receiver, assets, shares);
        if (shares == 0) revert SuperPool_ZeroShareDeposit(address(this));
        return shares;
    }

    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256) {
        accrueInterestAndFees();
        uint256 assets = _convertToAssetsWithTotals(shares, totalSupply(), lastTotalAssets, Math.Rounding.Ceil);
        _deposit(msg.sender, receiver, assets, shares);
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        accrueInterestAndFees();
        uint256 shares = _convertToSharesWithTotals(assets, totalSupply(), lastTotalAssets, Math.Rounding.Ceil);
        _withdraw(msg.sender, receiver, owner, assets, shares);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        accrueInterestAndFees();
        uint256 assets = _convertToAssetsWithTotals(shares, totalSupply(), lastTotalAssets, Math.Rounding.Floor);
        _withdraw(msg.sender, receiver, owner, assets, shares);
        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                              Only Owner
    //////////////////////////////////////////////////////////////*/

    function setPoolCap(uint256 poolId, uint256 cap) external onlyOwner {
        // add new pool
        if (poolCap[poolId] == 0 && cap != 0) _addPool(poolId);
        // remove existing pool
        else if (poolCap[poolId] != 0 && cap == 0) _removePool(poolId);
        // modify pool cap: if the cap is below the assets in the pool, it becomes withdraw-only
        else if (poolCap[poolId] != 0 && cap != 0) poolCap[poolId] = cap;
        else return; // handle pool == 0 && cap == 0

        emit PoolCapSet(poolId, cap);
    }

    function reorderDepositQueue(uint256[] calldata indexes) external onlyOwner {
        if (indexes.length != depositQueue.length) revert SuperPool_QueueLengthMismatch(address(this));
        depositQueue = _reorderQueue(depositQueue, indexes);
    }

    function reorderWithdrawQueue(uint256[] calldata indexes) external onlyOwner {
        if (indexes.length != withdrawQueue.length) revert SuperPool_QueueLengthMismatch(address(this));
        withdrawQueue = _reorderQueue(withdrawQueue, indexes);
    }

    function toggleAllocator(address _allocator) external onlyOwner {
        isAllocator[_allocator] = !isAllocator[_allocator];

        emit AllocatorUpdated(_allocator, isAllocator[_allocator]);
    }

    function setFee(uint256 _fee) external onlyOwner {
        accrueInterestAndFees();

        fee = _fee;

        emit SuperPoolFeeUpdated(_fee);
    }

    function setSuperpoolCap(uint256 _superPoolCap) external onlyOwner {
        superPoolCap = _superPoolCap;

        emit SuperPoolCapUpdated(_superPoolCap);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        accrueInterestAndFees();

        feeRecipient = _feeRecipient;

        emit SuperPoolFeeRecipientUpdated(_feeRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                           Asset Allocation
    //////////////////////////////////////////////////////////////*/

    struct ReallocateParams {
        address pool;
        uint256 assets;
    }

    function reallocate(ReallocateParams[] calldata withdraws, ReallocateParams[] calldata deposits) external {
        if (!isAllocator[msg.sender] && msg.sender != OwnableUpgradeable.owner()) {
            revert SuperPool_OnlyAllocatorOrOwner(address(this), msg.sender);
        }

        for (uint256 i; i < withdraws.length; ++i) {
            IERC4626(withdraws[i].pool).withdraw(withdraws[i].assets, address(this), address(this));
        }

        for (uint256 i; i < deposits.length; ++i) {
            IERC20(asset()).approve(deposits[i].pool, deposits[i].assets);
            IERC4626(deposits[i].pool).deposit(deposits[i].assets, address(this));
        }
    }

    /*//////////////////////////////////////////////////////////////
                               Internal
    //////////////////////////////////////////////////////////////*/

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        ERC4626Upgradeable._deposit(caller, receiver, assets, shares);
        _supplyToPools(assets);
        lastTotalAssets += assets;
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        _withdrawFromPools(assets);
        ERC4626Upgradeable._withdraw(caller, receiver, owner, assets, shares);
        lastTotalAssets -= assets;
    }

    function _maxWithdraw(address owner) internal view returns (uint256, uint256, uint256) {
        (uint256 feeShares, uint256 newTotalAssets) = _simulateFeeAccrual();

        uint256 assets =
            _convertToSharesWithTotals(balanceOf(owner), totalSupply() + feeShares, newTotalAssets, Math.Rounding.Floor);

        return (assets, totalSupply() + feeShares, newTotalAssets);
    }

    function _supplyToPools(uint256 assets) internal {
        for (uint256 i; i < depositQueue.length; ++i) {
            uint256 poolId = depositQueue[i];
            uint256 assetsInPool = pool.getAssetsOf(poolId, address(this));

            if (assetsInPool < poolCap[poolId]) {
                uint256 supplyAmt = poolCap[poolId] - assetsInPool;
                if (assets < supplyAmt) supplyAmt = assets;
                IERC20(asset()).forceApprove(address(pool), supplyAmt);

                try pool.deposit(poolId, supplyAmt, address(this)) {
                    assets -= supplyAmt;
                } catch {
                    IERC20(asset()).forceApprove(address(pool), 0);
                }

                if (assets == 0) return;
            }
        }
        if (assets != 0) revert SuperPool_AllCapsReached(address(this));
    }

    function _withdrawFromPools(uint256 assets) internal {
        uint256 assetsInSuperpool = IERC20(address(this)).balanceOf(asset());

        if (assetsInSuperpool >= assets) return;
        else assets -= assetsInSuperpool;

        for (uint256 i; i < withdrawQueue.length; ++i) {
            uint256 poolId = withdrawQueue[i];
            uint256 assetsInPool = pool.getAssetsOf(poolId, address(this));

            if (assetsInPool > 0) {
                uint256 withdrawAmt = (assetsInPool < assets) ? assetsInPool : assets;

                if (withdrawAmt > 0) {
                    // TODO
                    // try pool.withdraw(withdrawAmt, address(this), address(this)) {
                    //     assets -= withdrawAmt;
                    // } catch {}
                }

                if (assets == 0) return;
            }
        }
        if (assets != 0) revert SuperPool_NotEnoughLiquidity(address(this));
    }

    function _addPool(uint256 poolId) internal {
        if (pool.getPoolAssetFor(poolId) != asset()) revert SuperPool_PoolAssetMismatch(address(this), poolId);
        if (depositQueue.length == MAX_QUEUE_LENGTH) revert SuperPool_MaxQueueLengthReached(address(this));

        depositQueue.push(poolId);
        withdrawQueue.push(poolId);
    }

    function _removePool(uint256 poolId) internal onlyOwner {
        if (pool.getAssetsOf(poolId, address(this)) != 0) revert SuperPool_NonZeroPoolBalance(address(this), poolId);

        // gas intensive ops that shift the entire array to preserve order
        _removeFromQueue(depositQueue, poolId);
        _removeFromQueue(withdrawQueue, poolId);

        emit PoolRemoved(poolId);
    }

    function _reorderQueue(uint256[] storage queue, uint256[] calldata indexes)
        internal
        view
        returns (uint256[] memory)
    {
        bool[] memory seen = new bool[](indexes.length);

        uint256[] memory newQueue;

        for (uint256 i; i < indexes.length; ++i) {
            if (seen[indexes[i]]) revert SuperPool_InvalidQueue(address(this));
            newQueue[i] = queue[i];
            seen[indexes[i]] = true;
        }

        for (uint256 i = 1; i <= indexes.length; ++i) {
            if (!seen[i]) revert SuperPool_InvalidQueue(address(this));
        }

        return newQueue;
    }

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

    function _simulateFeeAccrual() internal view returns (uint256, uint256) {
        uint256 newTotalAssets = totalAssets();
        uint256 interestAccrued = (newTotalAssets > lastTotalAssets) ? newTotalAssets - lastTotalAssets : 0;
        if (interestAccrued == 0 || fee == 0) return (0, 0);

        uint256 feeAssets = interestAccrued.mulDiv(fee, WAD);
        uint256 feeShares =
            _convertToSharesWithTotals(feeAssets, totalSupply(), newTotalAssets - feeAssets, Math.Rounding.Floor);

        return (feeShares, newTotalAssets);
    }

    /*//////////////////////////////////////////////////////////////
                             Shares Math
    //////////////////////////////////////////////////////////////*/

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256) {
        (uint256 feeShares, uint256 newTotalAssets) = _simulateFeeAccrual();

        return _convertToSharesWithTotals(assets, totalSupply() + feeShares, newTotalAssets, rounding);
    }

    function _convertToSharesWithTotals(
        uint256 assets,
        uint256 newTotalSupply,
        uint256 newTotalAssets,
        Math.Rounding rounding
    ) internal view returns (uint256) {
        return assets.mulDiv(newTotalSupply + 10 ** _decimalsOffset(), newTotalAssets + 1, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256) {
        (uint256 feeShares, uint256 newTotalAssets) = _simulateFeeAccrual();

        return _convertToAssetsWithTotals(shares, totalSupply() + feeShares, newTotalAssets, rounding);
    }

    function _convertToAssetsWithTotals(
        uint256 shares,
        uint256 newTotalSupply,
        uint256 newTotalAssets,
        Math.Rounding rounding
    ) internal view returns (uint256) {
        return shares.mulDiv(newTotalAssets + 1, newTotalSupply + 10 ** _decimalsOffset(), rounding);
    }
}
