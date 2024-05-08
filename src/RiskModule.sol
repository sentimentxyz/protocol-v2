// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import {Position} from "./Position.sol";
import {RiskEngine} from "./RiskEngine.sol";
import {DebtData, AssetData} from "./PositionManager.sol";
// libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract RiskModule {
    using Math for uint256;

    uint256 public constant VERSION = 1;
    uint256 public immutable MIN_DEBT;
    RiskEngine public immutable RISK_ENGINE;
    uint256 public immutable LIQUIDATION_DISCOUNT;

    constructor(uint256 minDebt_, address riskEngine_, uint256 liquidationDiscount_) {
        MIN_DEBT = minDebt_;
        RISK_ENGINE = RiskEngine(riskEngine_);
        LIQUIDATION_DISCOUNT = liquidationDiscount_;
    }

    function isPositionHealthy(address position) external view returns (bool) {}

    function isValidLiquidation(address position, DebtData[] calldata debt, AssetData[] calldata assets)
        external
        view
        returns (bool)
    {}

    function getRiskData(address position) public view returns (uint256, uint256, uint256) {}
}
