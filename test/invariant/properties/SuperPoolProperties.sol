// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { BeforeAfter } from "../helpers/BeforeAfter.sol";

import { FuzzLibString } from "@fuzzlib/FuzzLibString.sol";
import { Vm } from "forge-std/Test.sol";
import { Pool } from "src/Pool.sol";

import { Action, Operation, PositionManager } from "src/PositionManager.sol";
import { SuperPool } from "src/SuperPool.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract SuperPoolProperties is BeforeAfter {
    /// @notice verifies shares may never be minted for free using previewDeposit()
    function superPool_SP_43(uint256 poolIndexSeed) public {
        SuperPool superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        uint256 sharesMinted = superPool.previewDeposit(0);
        fl.eq(sharesMinted, 0, "SP-43: previewDeposit() must not mint shares at no cost");
    }

    /// @notice verifies shares may never be minted for free using previewMint()
    function superPool_SP_44(uint256 poolIndexSeed, uint256 shares) public {
        SuperPool superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        require(shares > 0);
        uint256 assetsConsumed = superPool.previewMint(shares);
        fl.gt(assetsConsumed, 0, "SP-44: previewMint() must never mint shares at no cost");
    }

    /// @notice verifies shares may never be minted for free using convertToShares()
    function superPool_SP_45(uint256 poolIndexSeed) public {
        SuperPool superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        // note: the correctness of this property can't be tested using solmate as a reference impl. 0/n=0. best case
        // scenario, some other property gets set off.
        uint256 assetsWithdrawn = superPool.convertToShares(0);
        fl.eq(assetsWithdrawn, 0, "SP-45: convertToShares() must not allow shares to be minted at no cost");
    }

    /// @notice verifies assets may never be withdrawn for free using previewRedeem()
    function superPool_SP_46(uint256 poolIndexSeed) public {
        SuperPool superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        uint256 assetsWithdrawn = superPool.previewRedeem(0);
        fl.eq(assetsWithdrawn, 0, "SP-46: previewRedeem() must not allow assets to be withdrawn at no cost");
    }

    /// @notice verifies assets may never be withdrawn for free using previewWithdraw()
    function superPool_SP_47(uint256 poolIndexSeed, uint256 assets) public {
        SuperPool superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        require(assets > 0);
        uint256 sharesRedeemed = superPool.previewWithdraw(assets);
        fl.gt(sharesRedeemed, 0, "SP-47: previewWithdraw() must not allow assets to be withdrawn at no cost");
    }

    /// @notice verifies assets may never be withdrawn for free using convertToAssets()
    function superPool_SP_48(uint256 poolIndexSeed) public {
        SuperPool superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        // note: the correctness of this property can't be tested using solmate as a reference impl. 0/n=0. best case
        // scenario, some other property gets set off.
        uint256 assetsWithdrawn = superPool.convertToAssets(0);
        fl.eq(assetsWithdrawn, 0, "SP-48: convertToAssets() must not allow assets to be withdrawn at no cost");
    }

    /// @notice Indirectly verifies the rounding direction of convertToShares/convertToAssets is correct by attempting
    /// to
    ///         create an arbitrage by depositing, then withdrawing
    function superPool_SP_49(uint256 poolIndexSeed, uint256 amount) public {
        SuperPool superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        uint256 sharesMinted = superPool.convertToShares(amount);
        uint256 assetsWithdrawn = superPool.convertToAssets(sharesMinted);
        fl.gte(
            amount,
            assetsWithdrawn,
            "SP-49: Profit must not be extractable from a convertTo round trip (deposit, then withdraw)"
        );
    }

    /// @notice Indirectly verifies the rounding direction of convertToShares/convertToAssets is correct by attempting
    /// to
    ///         create an arbitrage by withdrawing, then depositing
    function superPool_SP_50(uint256 poolIndexSeed, uint256 amount) public {
        SuperPool superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        uint256 assetsWithdrawn = superPool.convertToAssets(amount);
        uint256 sharesMinted = superPool.convertToShares(assetsWithdrawn);
        fl.gte(
            amount,
            sharesMinted,
            "SP-50: Profit must not be extractable from a convertTo round trip (withdraw, then deposit)"
        );
    }

    /// @notice verifies Shares may never be minted for free using deposit()
    function superPool_SP_51(uint256 poolIndexSeed, uint256 userIndexSeed) public {
        SuperPool superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        address user = randomAddress(userIndexSeed);

        vm.prank(user);
        uint256 shares = superPool.deposit(0, user);
        fl.eq(shares, 0, "SP-51: Shares must not be minted for free using deposit()");
    }

    /// @notice verifies Shares may never be minted for free using mint()
    function superPool_SP_52(uint256 poolIndexSeed, uint256 userIndexSeed, uint256 shares) public {
        SuperPool superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        address user = randomAddress(userIndexSeed);
        require(shares > 0);

        vm.prank(user);
        uint256 assetsDeposited = superPool.mint(shares, user);

        fl.gt(assetsDeposited, 0, "SP-52: Shares must not be minted for free using mint()");
    }

    /// @notice verifies assets may never be withdrawn for free using withdraw()
    function superPool_SP_53(uint256 poolIndexSeed, uint256 userIndexSeed, uint256 assets) public {
        SuperPool superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        address user = randomAddress(userIndexSeed);
        require(assets > 0);

        vm.prank(user);
        uint256 sharesRedeemed = superPool.withdraw(assets, user, user);

        fl.gt(sharesRedeemed, 0, "SP-53: Assets must not be withdrawn for free using withdraw()");
    }

    /// @notice verifies assets may never be withdrawn for free using redeem()
    function superPool_SP_54(uint256 poolIndexSeed, uint256 userIndexSeed) public {
        SuperPool superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        address user = randomAddress(userIndexSeed);

        vm.prank(user);
        uint256 assetsWithdrawn = superPool.redeem(0, user, user);
        fl.eq(assetsWithdrawn, 0, "SP-54: Assets must not be withdrawn for free using redeem()");
    }

    struct DecimalsTemps {
        address asset;
        SuperPool superPool;
    }

    /// @notice verify `decimals()` should be larger than or equal to `asset.decimals()`
    function superPool_SP_55(uint256 poolIndexSeed) public {
        // PRE-CONDITIONS
        DecimalsTemps memory d;
        d.superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        d.asset = d.superPool.asset();
        fl.gte(
            d.superPool.decimals(),
            ERC20(d.asset).decimals(),
            "SP-55: The vault's share token should have greater than or equal to the number of decimals as the vault's asset token."
        );
    }

    struct InflationAttackTemps {
        address attacker;
        address receiver;
        address asset;
        uint256 assetsWithdrawn;
        SuperPool superPool;
    }

    /// @notice verify Accounting system must not be vulnerable to share price inflation griefing
    function superPool_SP_56(
        uint256 attackerIndexSeed,
        uint256 receiverIndexSeed,
        uint256 poolIndexSeed,
        uint256 inflateAmount
    ) public {
        // PRE-CONDITIONS
        InflationAttackTemps memory d;
        d.attacker = randomAddress(attackerIndexSeed);
        d.receiver = randomAddress(receiverIndexSeed);
        d.superPool = poolIndexSeed % 2 == 0 ? superPool1 : superPool2;
        d.asset = d.superPool.asset();

        // this has to be changed if there's deposit/withdraw fees
        uint256 lossThreshold = 0.999 ether;
        // vault is fresh
        require(d.superPool.totalAssets() == 0);
        require(d.superPool.totalSupply() == 0);

        // these minimums are to prevent 1-wei rounding errors from triggering the property
        require(inflateAmount > 10_000);
        uint256 victimDeposit = inflateAmount;
        // fund account
        asset1.mint(d.attacker, inflateAmount);
        asset2.mint(d.attacker, inflateAmount);
        vm.prank(d.attacker);
        IERC20(d.asset).approve(address(d.superPool), inflateAmount);

        vm.prank(d.attacker);
        uint256 shares = d.superPool.deposit(1, d.attacker);
        // attack only works when pps=1:1 + new vault
        require(shares == 1);
        require(d.superPool.totalAssets() == 1);

        // inflate pps
        vm.prank(d.attacker);
        IERC20(d.asset).transfer(address(d.superPool), inflateAmount - 1);

        // fund victim
        asset1.mint(d.receiver, victimDeposit);
        asset2.mint(d.receiver, victimDeposit);
        vm.prank(d.receiver);
        IERC20(d.asset).approve(address(d.superPool), type(uint256).max);

        fl.log("Amount of receiver's deposit:", victimDeposit);
        vm.prank(d.receiver);
        uint256 receiverShares = d.superPool.deposit(victimDeposit, d.receiver);
        fl.log("receiver Shares:", receiverShares);
        vm.prank(d.receiver);
        uint256 receiverWithdrawnFunds = d.superPool.redeem(receiverShares, d.receiver, d.receiver);
        fl.log("Amount of tokens receiver withdrew:", receiverWithdrawnFunds);

        uint256 victimLoss = victimDeposit - receiverWithdrawnFunds;
        fl.log("receiver Loss:", victimLoss);

        uint256 minRedeemedAmountNorm = (victimDeposit * lossThreshold) / 1 ether;

        fl.log("lossThreshold", lossThreshold);
        fl.log("minRedeemedAmountNorm", minRedeemedAmountNorm);
        fl.gt(
            receiverWithdrawnFunds,
            minRedeemedAmountNorm,
            "SP-56: Share inflation griefing possible, victim lost an amount over lossThreshold%"
        );
    }
}
