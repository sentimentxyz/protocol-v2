// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IStabilityPool.sol";

/**
 * @title StabilityPoolToken
 * @notice Minimal ERC20 wrapper for the  Stability Pool that represents feUSD deposit value
 * @dev This token is a view-only wrapper that allows the Stability Pool to be used with Sentiment's RiskModule
 *      which expects all position assets to be ERC20s. It represents feUSD deposit value in the pool.
 */
contract StabilityPoolToken is ERC20, Ownable {
    //  Stability Pool contract
    IStabilityPool public immutable stabilityPool;

    // feUSD contract address
    address public immutable feUSD;

    /**
     * @notice Initializes the wrapper token
     * @param _stabilityPool Address of the  Stability Pool contract
     * @param _feUSD Address of the feUSD token contract
     * @param _owner Address of the contract owner
     */
    constructor(
        address _stabilityPool,
        address _feUSD,
        address _owner
    ) ERC20("Felix Stability Pool feUSD", "fsfeUSD") Ownable() {
        stabilityPool = IStabilityPool(_stabilityPool);
        feUSD = _feUSD;
        _transferOwnership(_owner);
    }

    /**
     * @notice Get the feUSD deposit balance for an account
     * @dev Uses getCompoundedfeUSDDeposit for accurate compounded balance
     */
    function balanceOf(address account) public view override returns (uint256) {
        // Use getCompoundedfeUSDDeposit which includes earned rewards
        return stabilityPool.getCompoundedfeUSDDeposit(account);
    }

    /**
     * @notice Total supply returns the total feUSD deposits in the Stability Pool
     * @return The total feUSD deposits in the pool
     */
    function totalSupply() public view override returns (uint256) {
        // Use getTotalfeUSDDeposits which returns the total feUSD deposits with rewards
        return stabilityPool.getTotalfeUSDDeposits();
    }

    /**
     * @notice All transfer operations are disabled - this is a view-only wrapper
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert("Transfer not supported");
    }

    /**
     * @notice All transfer operations are disabled - this is a view-only wrapper
     */
    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        revert("TransferFrom not supported");
    }

    /**
     * @notice Approvals are not supported - this is a view-only wrapper
     */
    function approve(address, uint256) public pure override returns (bool) {
        revert("Approve not supported");
    }

    /**
     * @notice Always returns 0 since approvals are not supported
     */
    function allowance(
        address,
        address
    ) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the number of decimals for the token
     * @return 18 to match feUSD decimal places
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
