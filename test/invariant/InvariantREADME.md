## Sentiment Fuzz Suite

### Overview
Sentiment engaged Guardian Audits for an in-depth security review of the Sentiment Protocol, a leveraged lending protocol. This comprehensive evaluation, conducted from June 17th to June 27th, 2024, included the development of a specialized fuzzing suite to uncover complex logical errors. This suite was created during the review period and successfully delivered upon the audit's conclusion.

### Contents
BaseSentimentInvariant configures the Sentiment Protocol setup and actors used for fuzzing. 

All of the invariants reside in the following contracts:
* SuperPoolHandler.sol
* SuperPoolProperties.sol
* PoolHandler.sol
* PoolProperties.sol
* PositionManagerHandler.sol


### Setup And Run Instructions
To run invariant tests:
```shell
echidna ./invariant/invariants/SentimentInvariant.sol --contract SentimentInvariant --config echidna.yaml
```

### Changelog
To simplify gathering coverage, `SuperPool.accrue()` & `Pool.accrue()` are called at the beginning of select function handlers.
The preview functions do not account for pending interest and when pending interest was present the following invariants would not hold:
* SP-10
* SP-20
* SP-30
* SP-40

In the current state of the fuzzing suite, these invariants will hold due to pending interest being collected before any state changes are made.

***Note about liquidations:***
Due to the `_getMinReqAssetValue` (PO-19) issue of not requiring a position's asset list to have anything in it, many liquidations are DOSed and the following liquidation invariants do not reflect that.


### Invariants
## **SuperPool**
| **Invariant ID** | **Invariant Description** | **Passed** | **Remediation** | **Run Count** |
|:--------------:|:-----|:-----------:|:-----------:|:-----------:|
| **SP-01** | SuperPool.deposit() must consume exactly the number of assets requested  | PASS | | 1,000,000+
| **SP-02** | SuperPool.deposit() must credit the correct number of shares to the receiver | PASS | | 1,000,000+
| **SP-03** | SuperPool.deposit() must credit the correct number of assets to the pools in depositQueue | PASS | | 1,000,000+
| **SP-04** | SuperPool.deposit() must credit the correct number of shares to the pools in depositQueue | PASS | | 1,000,000+
| **SP-05** | SuperPool.deposit() must credit the correct number of shares to the SuperPool for the pools in depositQueue | PASS | | 1,000,000+
| **SP-06** | SuperPool.deposit() must update lastUpdated to the current block.timestamp for the pools in depositQueue | PASS |  | 1,000,000+
| **SP-07** | SuperPool.deposit() must credit pendingInterest to the totalBorrows asset balance for pools in depositQueue | PASS | | 1,000,000+
| **SP-08** | SuperPool.deposit() must transfer the correct number of assets to the base pool for pools in depositQueue | PASS | | 1,000,000+
| **SP-09** | SuperPool.deposit() must increase the lastTotalAssets by the number of assets provided | PASS | | 1,000,000+
| **SP-10** | SuperPool.deposit() must always mint greater than or equal to the shares predicted by previewDeposit() | PASS | | 1,000,000+
| **SP-11** | SuperPool.mint() must consume exactly the number of tokens requested | PASS | | 1,000,000+
| **SP-12** | SuperPool.mint() must credit the correct number of shares to the receiver | PASS | | 1,000,000+
| **SP-13** | SuperPool.mint() must credit the correct number of assets to the pools in depositQueue | PASS | | 1,000,000+
| **SP-14** | SuperPool.mint() must credit the correct number of shares to the pools in depositQueue | PASS | | 1,000,000+
| **SP-15** | SuperPool.mint() must credit the correct number of shares to the SuperPool for the pools in depositQueue | PASS | | 1,000,000+
| **SP-16** | SuperPool.mint() must update lastUpdated to the current block.timestamp for the pools in depositQueue | PASS | | 1,000,000+
| **SP-17** | SuperPool.mint() must credit pendingInterest to the totalBorrows asset balance for pools in depositQueue | PASS | | 1,000,000+
| **SP-18** | SuperPool.mint() must transfer the correct number of assets to the base pool for pools in depositQueue | PASS | | 1,000,000+
| **SP-19** | SuperPool.mint() must increase the lastTotalAssets by the number of assets consumed | PASS | | 1,000,000+
| **SP-20** | SuperPool.mint() must always consume less than or equal to the tokens predicted by previewMint() | PASS | | 1,000,000+
| **SP-21** | SuperPool.withdraw() must credit the correct number of assets to the receiver | PASS | | 1,000,000+
| **SP-22** | SuperPool.withdraw() must deduct the correct number of shares from the owner | PASS | | 1,000,000+
| **SP-23** | SuperPool.withdraw() must withdraw the correct number of assets from the pools in withdrawQueue | **FAIL** | | 1,000,000+
| **SP-24** | SuperPool.withdraw() must withdraw the correct number of shares from the pools in withdrawQueue | **FAIL** | | 1,000,000+
| **SP-25** | SuperPool.withdraw() must deduct the correct number of shares from the SuperPool share balance for the pools in withdrawQueue | **FAIL** | | 1,000,000+
| **SP-26** | SuperPool.withdraw() must update lastUpdated to the current block.timestamp for the pools in withdrawQueue | PASS | | 1,000,000+
| **SP-27** | SuperPool.withdraw() must credit pendingInterest to the totalBorrows asset balance for pools in withdrawQueue | PASS | | 1,000,000+
| **SP-28** | SuperPool.withdraw() must transfer the correct number of assets from the base pool for pools in withdrawQueue | **FAIL** | | 1,000,000+
| **SP-29** | SuperPool.withdraw() must decrease the lastTotalAssets by the number of assets consumed | PASS | | 1,000,000+
| **SP-30** | SuperPool.withdraw() must redeem less than or equal to the number of shares predicted by previewWithdraw() | PASS | | 1,000,000+
| **SP-31** | SuperPool.redeem() must credit the correct number of assets to the receiver | PASS | | 1,000,000+
| **SP-32** | SuperPool.redeem() must deduct the correct number of shares from the owner | PASS | | 1,000,000+
| **SP-33** | SuperPool.redeem() must withdraw the correct number of assets to the pools in withdrawQueue | **FAIL** | | 1,000,000+
| **SP-34** | SuperPool.redeem() must withdraw the correct number of shares from the pools in withdrawQueue | **FAIL** | | 1,000,000+
| **SP-35** | SuperPool.redeem() must deduct the correct number of shares from the SuperPool share balance for the pools in withdrawQueue | **FAIL** | | 1,000,000+
| **SP-36** | SuperPool.redeem() must update lastUpdated to the current block.timestamp for the pools in withdrawQueue | PASS | | 1,000,000+
| **SP-37** | SuperPool.redeem() must credit pendingInterest to the totalBorrows asset balance for pools in withdrawQueue | PASS | | 1,000,000+
| **SP-38** | SuperPool.redeem() must transfer the correct number of assets from the pools in withdrawQueue | **FAIL** | | 1,000,000+
| **SP-39** | SuperPool.redeem() must decrease the lastTotalAssets by the number of assets consumed | PASS | | 1,000,000+
| **SP-40** | SuperPool.redeem() must withdraw greater than or equal to the number of assets predicted by previewRedeem() | PASS | | 1,000,000+
| **SP-41** | The lastTotalAssets value before calling accrue should always be <= after calling it | **FAIL** | | 1,000,000+
| **SP-42** | Fee recipient shares after should be greater than or equal to fee recipient shares before | PASS | | 1,000,000+
| **SP-43** | previewDeposit() must not mint shares at no cost | PASS | | 1,000,000+
| **SP-44** | previewMint() must never mint shares at no cost | PASS | | 1,000,000+
| **SP-45** | convertToShares() must not allow shares to be minted at no cost | PASS | | 1,000,000+
| **SP-46** | previewRedeem() must not allow assets to be withdrawn at no cost | PASS | | 1,000,000+
| **SP-47** | previewWithdraw() must not allow assets to be withdrawn at no cost | PASS | | 1,000,000+
| **SP-48** | convertToAssets() must not allow assets to be withdrawn at no cost | PASS | | 1,000,000+
| **SP-49** | Profit must not be extractable from a convertTo round trip (deposit, then withdraw) | PASS | | 1,000,000+
| **SP-50** | Profit must not be extractable from a convertTo round trip (withdraw, then deposit) | PASS | | 1,000,000+
| **SP-51** | Shares must not be minted for free using deposit() | PASS | | 1,000,000+
| **SP-52** | Shares must not be minted for free using mint() | PASS | | 1,000,000+
| **SP-53** | Assets must not be withdrawn for free using withdraw() | PASS | | 1,000,000+
| **SP-54** | Assets must not be withdrawn for free using redeem() | PASS | | 1,000,000+
| **SP-55** | The vault's share token should have greater than or equal to the number of decimals as the vault's asset token | PASS | | 1,000,000+
| **SP-56** | Share inflation attack possible, victim lost an amount over lossThreshold% | PASS | | 1,000,000+
## **Pool**
| **Invariant ID** | **Invariant Description** | **Passed** | **Remediation** | **Run Count** |
|:--------------:|:-----|:-----------:|:-----------:|:-----------:|
| **PO-01** | Pool.deposit() must increase poolId assets by assets and pending interest  | PASS | | 1,000,000+
| **PO-02** | Pool.deposit() must increase poolId shares by sharesDeposited | PASS | | 1,000,000+
| **PO-03** | Pool.deposit() must consume the correct number of assets | PASS | | 1,000,000+
| **PO-04** | Pool.deposit() must credit the correct number of shares to receiver | PASS | | 1,000,000+
| **PO-05** | Pool.deposit() must transfer the correct number of assets to pool | PASS | | 1,000,000+
| **PO-06** | Pool.deposit() must update lastUpdated to the current block.timestamp | PASS |  | 1,000,000+
| **PO-07** | Pool.deposit() must credit pendingInterest to the totalBorrows asset balance for poolID | PASS | | 1,000,000+
| **PO-08** | Pool.redeem() must decrease poolId assets by assetsRedeemed + pendingInterest | PASS | | 1,000,000+
| **PO-09** | Pool.redeem() must decrease poolId shares by shares amount | PASS | | 1,000,000+
| **PO-10** | Pool.redeem() must credit the correct number of assets to receiver | PASS | | 1,000,000+
| **PO-11** | Pool.redeem() must consume the correct number of shares from receiver | PASS | | 1,000,000+
| **PO-12** | Pool.redeem() must transfer the correct number of assets to receiver | PASS | | 1,000,000+
| **PO-13** | Pool.redeem() must update lastUpdated to the current block.timestamp | PASS | | 1,000,000+
| **PO-14** | Pool.redeem() must credit pendingInterest to the totalBorrows asset balance for poolID | PASS | | 1,000,000+
| **PO-15** | The pool.totalAssets.assets value before calling accrue should always be <= after calling it. | PASS | | 1,000,000+
| **PO-16** | The pool.totalBorrows.assets value before calling accrue should always be <= after calling it | PASS | | 1,000,000+
| **PO-17** | Fee recipient shares after should be greater than or equal to fee recipient shares before | PASS | | 1,000,000+
| **PO-18** | User debt value should be equal to 0 or greater than or equal to MIN_DEBT | PASS | | 1,000,000+
| **PO-19** | Min Required Position Asset Value should be greater than total position debt value | **FAIL** | | 1,000,000+
| **PO-20** | The pool.totalAssets.shares values should always equal the sum of the shares of all users | PASS | | 1,000,000+
| **PO-21** | The pool.totalBorrows.shares values should always equal the sum of the borrow share balances of all borrowers | PASS | | 1,000,000+
## **PositionManager**
| **Invariant ID** | **Invariant Description** | **Passed** | **Remediation** | **Run Count** |
|:--------------:|:-----|:-----------:|:-----------:|:-----------:|
| **PM-01** | PositionManager.newPosition() should set auth to true for owner  | PASS | | 1,000,000+
| **PM-02** | PositionManager.newPosition() should set ownerOf position to owner | PASS | | 1,000,000+
| **PM-03** | PositionManager.deposit() must consume the correct amount of assets | PASS | | 1,000,000+
| **PM-04** | PositionManager.transfer() must consume asset amount from position | PASS | | 1,000,000+
| **PM-05** | PositionManager.transfer() must credit asset amount to recipient | PASS | | 1,000,000+
| **PM-06** | PositionManager.borrow() must credit amount of assets to poolId total borrow asset balance | PASS |  | 1,000,000+
| **PM-07** | PositionManager.borrow() must credit amount of shares to poolId total borrow share balance | PASS | | 1,000,000+
| **PM-08** | PositionManager.borrow() must credit amount of shares to poolId position share balance | PASS | | 1,000,000+
| **PM-09** | PositionManager.borrow() must credit fee amount to feeRecipient | PASS | | 1,000,000+
| **PM-10** | PositionManager.borrow() must credit the correct number of assets to position | PASS | | 1,000,000+
| **PM-11** | PositionManager.borrow() must add poolId to debtPools | PASS | | 1,000,000+
| **PM-12** | Position debt pools should be less than or equal to max debt pools | PASS | | 1,000,000+
| **PM-13** | PositionManager.repay() must credit assets to pool | PASS | | 1,000,000+
| **PM-14** | PositionManager.repay() must consume asset amount from position | PASS | | 1,000,000+
| **PM-15** | PositionManager.repay() must consume amount of assets from poolId total borrow asset balance | PASS | | 1,000,000+
| **PM-16** | PositionManager.repay() must consume amount of shares from poolId total borrow share balance | PASS | | 1,000,000+
| **PM-17** | PositionManager.repay() must consume amount of shares from poolId position share balance | PASS | | 1,000,000+
| **PM-18** | PositionManager.repay() must delete poolId from debtPools if position has no borrows | PASS | | 1,000,000+
| **PM-19** | PositionManager.addToken() must add asset to position assets list | PASS | | 1,000,000+
| **PM-20** | Position assets length should be less than or equal to max assets | PASS | | 1,000,000+
| **PM-21** | PositionManager.removeToken() must remove asset from position assets list | PASS | | 1,000,000+
| **PM-22** | PositionManager.liquidate() must credit the correct number of debt assets to pool | PASS | | 1,000,000+
| **PM-23** | PositionManager.liquidate() must credit the correct number of debt assets to poolPositionManager.liquidate() must credit the correct number of assets to liquidator | PASS | | 1,000,000+
| **PM-24** | PositionManager.liquidate() must credit the correct number of fee assets to owner | PASS | | 1,000,000+
| **PM-25** | PositionManager.liquidate() must consume the correct number of position assets from position | PASS | | 1,000,000+
| **PM-26** | Position must be healthy after liquidation | PASS | | 1,000,000+
| **PM-27** | PositionManager.liquidate() must consume the correct number of assets from the pools in debtData | PASS | | 1,000,000+
| **PM-28** | PositionManager.liquidate() must consume the correct number of shares from the pools in debtData | PASS | | 1,000,000+
| **PM-29** | PositionManager.liquidate() must consume amount of shares from poolId position share balance | PASS | | 1,000,000+
| **PM-30** | PositionManager.liquidate() must update lastUpdated to the current block.timestamp for the pools in debtData | PASS | | 1,000,000+
| **PM-31** | PositionManager.liquidate() must delete poolId from debtPools if position has no borrows | PASS | | 1,000,000+