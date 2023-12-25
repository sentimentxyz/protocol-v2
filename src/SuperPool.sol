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

    /// A mapping of completed withdraw hashes
    mapping(bytes32 => bool) public completedWithdraws;

    /// An internal mapping of Pool => Pool Cap, incldudes an array of pools with non zero cap.
    PoolCapMapping.PoolCapMappingStorage internal poolCaps;

    /// The cumlative deposit cap for all pools
    uint256 public totalPoolCap;

    event PoolCapSet(address indexed pool, uint256 amt);
    event PoolDeposit(address indexed pool, uint256 assets);
    event PoolWithdraw(address indexed pool, uint256 assets);
    event EnquedWithdraw(
        uint256 indexed assets,
        uint256 indexed deadline,
        bytes32 indexed salt,
        address who
    );

    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        address owner
    ) Ownable(owner) ERC20(_name, _symbol) ERC4626(IERC20(_asset)) {}

    ////////////////////////// Only Owner //////////////////////////

    function setPoolCap(address _pool, uint256 assets) external onlyOwner {
        IERC4626 pool = IERC4626(_pool);

        require(
            pool.previewRedeem(pool.balanceOf(address(this))) <= assets,
            "SuperPool: cap too low"
        );

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

    function poolDeposit(address _pool, uint256 assets) external onlyOwner {
        IERC4626 pool = IERC4626(_pool);

        IERC20(this.asset()).approve(address(pool), assets);
        IERC4626(pool).deposit(assets, address(this));
        require(IERC4626(pool).balanceOf(address(this)) <= poolCap(pool));
        emit PoolDeposit(_pool, assets);
    }

    function poolWithdraw(address pool, uint256 assets) external onlyOwner {
        _poolWithdraw(IERC4626(pool), assets);
    }

    ////////////////////////// Withdraw //////////////////////////

    function withdrawWithPath(
        uint256 assets,
        uint256[] memory path
    ) external whenNotPaused {
        _withdrawWithPath(assets, path);

        withdraw(assets, msg.sender, msg.sender);
    }

    function withdrawEnque(
        uint256 assets,
        uint256 deadline,
        bytes32 salt
    ) external whenNotPaused {
        bytes32 _hash = hashWithdraw(assets, deadline, salt, msg.sender);

        require(
            !completedWithdraws[_hash],
            "SuperPool: withdraw already completed"
        );

        emit EnquedWithdraw(assets, deadline, salt, msg.sender);
    }

    function proceessWithdraw(
        uint256 assets,
        uint256 deadline,
        bytes32 salt,
        address onBehalfOf,
        uint256[] memory path
    ) external whenNotPaused {
        bytes32 _hash = hashWithdraw(assets, deadline, salt, onBehalfOf);

        require(
            !completedWithdraws[_hash],
            "SuperPool: withdraw already completed"
        );

        completedWithdraws[_hash] = true;

        _withdrawWithPath(assets, path);

        // We want touse the internal withdraw function here to avoid the msg.sender 
        // check that the public withdraw function would force on us. We do this because if not
        // whoever fullfills the withdraw would need approval
        _withdraw({
            caller: onBehalfOf, 
            receiver: onBehalfOf, 
            owner: onBehalfOf, 
            assets: assets, 
            shares: previewWithdraw(assets)
        });
    }

    ////////////////////////// Internal //////////////////////////

    function _poolWithdraw(IERC4626 pool, uint256 assets) internal {
        pool.withdraw(assets, address(this), address(this));
        emit PoolWithdraw(address(pool), assets);
    }

    function _withdrawWithPath(
        uint256 assets,
        uint256[] memory path
    ) internal {
        require(
            IERC20(this.asset()).balanceOf(address(this)) < assets,
            "SuperPool: Path not needed to complete withdrawl"
        );

        for (uint256 i = 0; i < path.length; i++) {
            uint256 _assets = path[i];
            if (_assets != 0) {
                _poolWithdraw(poolCaps.pool(i), _assets);
            }
        }
    }

    ////////////////////////// Overrides //////////////////////////

    function totalAssets() public view override returns (uint256 total) {
        uint256 len = poolCaps.length();
        for (uint256 i = 0; i < len; i++) {
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

    function hashWithdraw(
        uint256 assets,
        uint256 deadline,
        bytes32 salt,
        address onBehalfOf
    ) public view returns (bytes32) {
        uint256 chainId;

        assembly {
            chainId := chainid()
        }

        return
            keccak256(
                abi.encodePacked(
                    // domain
                    keccak256(
                        abi.encodePacked(keccak256("Sentiment V2"), chainId)
                    ),
                    assets,
                    deadline,
                    salt,
                    onBehalfOf
                )
            );
    }
}
