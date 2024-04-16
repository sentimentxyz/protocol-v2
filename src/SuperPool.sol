// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {Pool} from "./Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
// libraries
import {IterableSet} from "./lib/IterableSet.sol";
//contracts
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

// inspired by yearn v3 and metamorpho erc4626 vaults
contract Superpool is OwnableUpgradeable, PausableUpgradeable, ERC4626Upgradeable {
    /*//////////////////////////////////////////////////////////////
                               Storage
    //////////////////////////////////////////////////////////////*/

    uint256 public fee;
    uint256 public superpoolCap;

    address[] public depositQueue;
    address[] public withdrawQueue;
    mapping(address pool => uint256 cap) public poolCapFor;

    mapping(address => bool) isAllocator;

    /*//////////////////////////////////////////////////////////////
                                Event
    //////////////////////////////////////////////////////////////*/

    event PoolAdded(address pool);
    event PoolRemoved(address pool);
    event SuperpoolFeeUpdated(uint256 fee);
    event PoolCapSet(address pool, uint256 cap);
    event SuperpoolCapUpdated(uint256 superpoolCap);
    event AllocatorUpdated(address allocator, bool isAllocator);

    /*//////////////////////////////////////////////////////////////
                                Error
    //////////////////////////////////////////////////////////////*/

    error Superpool_InvalidQueue(address superpool);
    error Superpool_QueueLengthMismatch(address superpool);
    error SuperPool_PoolAssetMismatch(address superPool, address pool);
    error Superpool_NonZeroPoolBalance(address superpool, address pool);
    error SuperPool_OnlyAllocatorOrOwner(address superPool, address sender);

    /*//////////////////////////////////////////////////////////////
                              Initialize
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address asset_, uint256 fee_, uint256 superpoolCap_, string memory name_, string memory symbol_)
        public
        initializer
    {
        OwnableUpgradeable.__Ownable_init(msg.sender);
        PausableUpgradeable.__Pausable_init();
        ERC20Upgradeable.__ERC20_init(name_, symbol_);
        ERC4626Upgradeable.__ERC4626_init(IERC20(asset_));

        fee = fee_;
        superpoolCap = superpoolCap_;
    }

    /*//////////////////////////////////////////////////////////////
                            External View
    //////////////////////////////////////////////////////////////*/

    function getPools() external view returns (address[] memory) {
        return depositQueue;
    }

    function getPoolCount() external view returns (uint256) {
        return depositQueue.length;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 View Overrides
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view override returns (uint256) {
        uint256 assets = IERC20(ERC4626Upgradeable.asset()).balanceOf(address(this));

        for (uint256 i; i < depositQueue.length; ++i) {
            IERC4626 pool = IERC4626(depositQueue[i]);
            assets += pool.previewRedeem(pool.balanceOf(address(this)));
        }

        return assets;
    }

    function maxDeposit(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        return superpoolCap > assets ? (superpoolCap - assets) : 0;
    }

    function maxMint(address) public view override returns (uint256) {
        return previewDeposit(maxDeposit(address(0)));
    }

    /*//////////////////////////////////////////////////////////////
                          ERC4626 Overrides
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        return ERC4626Upgradeable.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256) {
        return ERC4626Upgradeable.mint(shares, receiver);
    }

    /*//////////////////////////////////////////////////////////////
                              Only Owner
    //////////////////////////////////////////////////////////////*/

    function updatePoolCap(address pool, uint256 cap) external onlyOwner {
        if (poolCapFor[pool] == 0 && cap != 0) _addPool(pool); // add new pool

        else if (poolCapFor[pool] != 0 && cap == 0) _removePool(pool); // remove existing pool

        else if (poolCapFor[pool] != 0 && cap != 0) poolCapFor[pool] = cap; // modify pool cap

        else return; // handle pool == 0 && cap == 0

        emit PoolCapSet(pool, cap);
    }

    function reorderDepositQueue(uint256[] calldata indexes) external onlyOwner {
        if (indexes.length != depositQueue.length) revert Superpool_QueueLengthMismatch(address(this));
        depositQueue = _reorderQueue(indexes, depositQueue);
    }

    function reorderWithdrawQueue(uint256[] calldata indexes) external onlyOwner {
        if (indexes.length != withdrawQueue.length) revert Superpool_QueueLengthMismatch(address(this));
        withdrawQueue = _reorderQueue(indexes, withdrawQueue);
    }

    function toggleAllocator(address _allocator) external onlyOwner {
        isAllocator[_allocator] = !isAllocator[_allocator];

        emit AllocatorUpdated(_allocator, isAllocator[_allocator]);
    }

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;

        emit SuperpoolFeeUpdated(_fee);
    }

    function setSuperpoolCap(uint256 _superpoolCap) external onlyOwner {
        superpoolCap = _superpoolCap;

        emit SuperpoolCapUpdated(_superpoolCap);
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

    function _addPool(address pool) internal {
        if (Pool(pool).asset() != asset()) revert SuperPool_PoolAssetMismatch(address(this), pool);

        depositQueue.push(pool);
        withdrawQueue.push(pool);
    }

    function _removePool(address pool) internal onlyOwner {
        if (IERC4626(pool).balanceOf(address(this)) != 0) revert Superpool_NonZeroPoolBalance(address(this), pool);

        // gas intensive ops that shift the entire array to preserve order
        _removeFromQueue(depositQueue, pool);
        _removeFromQueue(withdrawQueue, pool);

        emit PoolRemoved(pool);
    }

    function _reorderQueue(uint256[] calldata indexes, address[] storage queue)
        internal
        view
        returns (address[] memory)
    {
        bool[] memory seen = new bool[](indexes.length);

        address[] memory newQueue;

        for (uint256 i; i < indexes.length; ++i) {
            if (seen[indexes[i]]) revert Superpool_InvalidQueue(address(this));
            newQueue[i] = queue[i];
            seen[indexes[i]] = true;
        }

        for (uint256 i = 1; i <= indexes.length; ++i) {
            if (!seen[i]) revert Superpool_InvalidQueue(address(this));
        }

        return newQueue;
    }

    function _removeFromQueue(address[] storage queue, address pool) internal {
        uint256 toRemoveIdx;
        for (uint256 i; i < queue.length; ++i) {
            if (queue[i] == pool) {
                toRemoveIdx = i;
                break;
            }
        }
        for (uint256 i = toRemoveIdx; i < queue.length - 1; ++i) {
            queue[i] = queue[i + 1];
        }
        queue.pop();
    }
}
