// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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

    event PoolCapSet(uint256 poolCap);

    event OriginationFeeSet(uint256 originationFee);

    event InterestFeeSet(uint256 interestFee);

    event RateModelUpdateRejected();

    event RateModelUpdateAccepted(address rateModel);

    event RateModelUpdateRequested();

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    event PoolInitialized(address indexed owner, uint256 poolId, PoolData poolData);
}
