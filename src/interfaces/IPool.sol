// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Pool} from "../Pool.sol";

interface IPool {
    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @dev emitted on repay()
    /// @param position address to position for which debt was repaid
    /// @param asset debt asset for this pool
    /// @param amount amount of debt repaid, in debt asset units
    event Repay(address indexed position, address indexed asset, uint256 amount);

    /// @dev emitted on borrow()
    /// @param position address to position which borrowed funds
    /// @param asset debt asset for this pool
    /// @param amount amount of funds borrowed, in debt asset units
    event Borrow(address indexed position, address indexed asset, uint256 amount);

    event PoolCapSet(uint256 indexed poolId, uint128 poolCap);

    event PoolOwnerSet(uint256 indexed poolId, address owner);

    event OriginationFeeSet(uint256 indexed poolId, uint128 originationFee);

    event InterestFeeSet(uint256 indexed poolId, uint128 interestFee);

    event RateModelUpdateRejected(uint256 indexed poolId, address rateModel);

    event RateModelUpdated(uint256 indexed poolId, address rateModel);

    event RateModelUpdateRequested(uint256 indexed poolId, address rateModel);

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    event PoolInitialized(address indexed owner, uint256 indexed poolId, Pool.PoolData poolData);
}
