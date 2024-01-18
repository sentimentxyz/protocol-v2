// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IRiskManager} from "src/interfaces/IRiskManager.sol";
import {IPosition} from "src/interfaces/IPosition.sol";
import {IPool} from "src/interfaces/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IterableMapAddress} from "src/lib/IterableMapAddress.sol";
import {RiskEngineBase} from "src/risk/RiskEngineBase.sol";

contract Type2HealthCheck is RiskEngineBase {
    /// @dev this type of position has multiple pools, and only one collateral token.
    /// @dev for each pool we get the LTV and compute the minimum amount of collateral needed to be healthy.
    /// @dev we then sum up the total amount of collateral needed and compare it to the current amount of collateral.
    function isPositionHealthy(address position) external view returns (bool) {
        IPosition _position = IPosition(position);
        address asset = _position.getAssets()[0];
        uint256 totalCollateralNeeded;

        address[] memory pools = _position.getDebtPools();
        for (uint256 i; i < pools.length; ++i) {
            uint256 borrowsValue = _borrowValue(position, pools[i]);
            uint256 ltvBP = IPool(pools[i]).ltv(asset);

            totalCollateralNeeded = borrowsValue * 10000 / ltvBP;
        }
        
        // todo how to use the indivual oracles for each pool
        return _collateralValue(position, pools[0], asset) > totalCollateralNeeded;
    }
}