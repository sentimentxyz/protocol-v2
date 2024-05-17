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
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { Owned } from "lib/solmate/src/auth/Owned.sol";
//contracts
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { console } from "forge-std/console.sol";

// inspired by yearn v3 and metamorpho vaults
contract SuperPool is ERC20, Owned(msg.sender) {
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

    mapping(address => bool) public isAllocator;

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
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

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

    IERC20 public immutable asset;

    constructor( address _pool, SuperPoolInitParams memory params) ERC20(params.name, params.symbol, 18) {
        asset = IERC20(params.asset);
        pool = Pool(_pool);

        fee = params.fee;
        feeRecipient = params.feeRecipient;
        superPoolCap = params.superPoolCap;
    }

    struct SuperPoolInitParams {
        address asset;
        address feeRecipient;
        uint256 fee;
        uint256 superPoolCap;
        string name;
        string symbol;
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
        if (feeShares != 0) _mint(feeRecipient, feeShares);
        lastTotalAssets = newTotalAssets;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 View Overrides
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view returns (uint256) {
        uint256 assets = IERC20(asset).balanceOf(address(this));

        for (uint256 i; i < depositQueue.length; ++i) {
            assets += pool.getAssetsOf(depositQueue[i], address(this));
        }

        return assets;
    }

    function maxDeposit(address) public view returns (uint256) {
        uint256 assets = totalAssets();
        return superPoolCap > assets ? (superPoolCap - assets) : 0;
    }

    function maxMint(address) public view returns (uint256) {
        return convertToShares(maxDeposit(address(0)));
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        (uint256 assets,,) = _maxWithdraw(owner);
        return assets;
    }

    function maxRedeem(address owner) public view returns (uint256) {
        (uint256 assets,,) = _maxWithdraw(owner);

        return convertToShares(assets);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC4626 Overrides
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) public returns (uint256) {
        accrueInterestAndFees();
        uint256 shares = convertToShares(assets);
        _deposit(receiver, assets, shares);
        if (shares == 0) revert SuperPool_ZeroShareDeposit(address(this));
        return shares;
    }

    function mint(uint256 shares, address receiver) public returns (uint256) {
        accrueInterestAndFees();
        uint256 assets = convertToAssets(shares);
        _deposit(receiver, assets, shares);
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256) {
        accrueInterestAndFees();
        uint256 shares = convertToShares(assets);
        _withdraw(receiver, owner, assets, shares);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) public returns (uint256) {
        accrueInterestAndFees();
        uint256 assets = convertToAssets(shares);
        _withdraw(receiver, owner, assets, shares);
        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                              Only Owner
    //////////////////////////////////////////////////////////////*/

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
        }
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
        uint256 pool;
        uint256 assets;
    }

    function reallocate(ReallocateParams[] calldata withdraws, ReallocateParams[] calldata deposits) external {
        if (!isAllocator[msg.sender] && msg.sender != owner) {
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


    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDiv(supply, lastTotalAssets, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDiv(lastTotalAssets, supply, Math.Rounding.Floor);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDiv(lastTotalAssets, supply, Math.Rounding.Ceil);
    }

    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDiv(supply, lastTotalAssets, Math.Rounding.Ceil);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return convertToAssets(shares);
    }

    /*//////////////////////////////////////////////////////////////
                               Internal
    //////////////////////////////////////////////////////////////*/

    function _deposit(address receiver, uint256 assets, uint256 shares) internal {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
                _supplyToPools(assets);
        lastTotalAssets += assets;
    }

    function _withdraw(address receiver, address owner, uint256 assets, uint256 shares)
        internal
    {
        _withdrawFromPools(assets);

        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);

        lastTotalAssets -= assets;
    }

    function _maxWithdraw(address owner) internal view returns (uint256, uint256, uint256) {
        (uint256 feeShares, uint256 newTotalAssets) = _simulateFeeAccrual();

        uint256 assets =
            convertToShares(balanceOf[owner]);

        return (assets, totalSupply + feeShares, newTotalAssets);
    }

    function _supplyToPools(uint256 assets) internal {
        for (uint256 i; i < depositQueue.length; ++i) {
            uint256 poolId = depositQueue[i];
            uint256 assetsInPool = pool.getAssetsOf(poolId, address(this));

            if (assetsInPool < poolCap[poolId]) {
                uint256 supplyAmt = poolCap[poolId] - assetsInPool;
                if (assets < supplyAmt) supplyAmt = assets;
                IERC20(asset).forceApprove(address(pool), supplyAmt);

                try pool.deposit(poolId, supplyAmt, address(this)) {
                    assets -= supplyAmt;
                } catch {
                    IERC20(asset).forceApprove(address(pool), 0);
                }

                if (assets == 0) return;
            }
        }
        if (assets != 0) revert SuperPool_AllCapsReached(address(this));
    }

    function _withdrawFromPools(uint256 assets) internal {
        uint256 assetsInSuperpool = IERC20(address(this)).balanceOf(address(asset));

        console.log("wt2");

        if (assetsInSuperpool >= assets) return;
        else assets -= assetsInSuperpool;


        for (uint256 i; i < withdrawQueue.length; ++i) {
            uint256 poolId = withdrawQueue[i];
            uint256 assetsInPool = pool.getAssetsOf(poolId, address(this));

            if (assetsInPool > 0) {
                uint256 withdrawAmt = (assetsInPool < assets) ? assetsInPool : assets;

                console.log("wtf");

                if (withdrawAmt > 0) {
                    // TODO replace with withdraw logic
                    try pool.redeem(poolId, withdrawAmt, address(this), address(this)) {
                        assets -= withdrawAmt;
                        console.log("moooooooooooose");
                    } catch {
                        console.log("bad");
                    }
                }

                if (assets == 0) return;
            }
        }
        if (assets != 0) revert SuperPool_NotEnoughLiquidity(address(this));
    }

    function _addPool(uint256 poolId) internal {
        if (pool.getPoolAssetFor(poolId) != address(asset)) revert SuperPool_PoolAssetMismatch(address(this), poolId);
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
        if (interestAccrued == 0 || fee == 0) return (0, newTotalAssets);

        uint256 feeAssets = interestAccrued.mulDiv(fee, WAD);
        uint256 feeShares = convertToShares(feeAssets);

        return (feeShares, newTotalAssets);
    }
}
