# Withdrawing from Sentiment V2 SuperPools on HyperEVM

The Sentiment V2 interface has been deprecated after the protocol was wound down.
If you still have funds lent through a Sentiment V2 SuperPool on HyperEVM, you can
withdraw directly from the SuperPool contract on HyperEVMScan.

This guide is for HyperEVM mainnet, chain ID `999`, using HyperEVMScan: <https://hyperevmscan.io>.

## SuperPool Contracts

Use the SuperPool contract for the asset you deposited:

| SuperPool | Contract |
| --- | --- |
| HYPE | [`0x2831775cb5e64b1d892853893858a261e898fbeb`](https://hyperevmscan.io/address/0x2831775cb5e64b1d892853893858a261e898fbeb) |
| USDT0 | [`0x34B2B0DE7d288e79bbcfCEe6C2a222dAe25fF88D`](https://hyperevmscan.io/address/0x34B2B0DE7d288e79bbcfCEe6C2a222dAe25fF88D) |
| USDe | [`0xe45E7272DA7208C7a137505dFB9491e330BF1a4e`](https://hyperevmscan.io/address/0xe45E7272DA7208C7a137505dFB9491e330BF1a4e) |

## Before You Start

You need:

- The wallet that holds your SuperPool shares.
- A small amount of native HYPE in that wallet for gas.
- The correct network selected in your wallet: HyperEVM mainnet, chain ID `999`.
- The SuperPool contract address for the asset you want to withdraw.

Amounts on the contract page are entered as raw token units.
Check the SuperPool's `decimals()` value on the `Read Contract` page before entering an amount.
For example, if `decimals()` returns `18`, then `1` token is entered as `1000000000000000000`.

## Step 1: Open the SuperPool Contract

1. Open the relevant SuperPool link from the table above.
2. Confirm you are on `hyperevmscan.io`.
3. Open the `Contract` tab.
4. Open `Read Contract` first. You will use it to check your balance and the available liquidity.

## Step 2: Check Your Withdrawable Amount

On the SuperPool `Read Contract` page:

1. Find `balanceOf`.
2. Enter your wallet address.
3. Click `Query`.

If `balanceOf` returns `0`, that wallet does not hold shares in that SuperPool.

Next, check how much underlying asset you can withdraw right now:

1. Find `maxWithdraw`.
2. Enter your wallet address as `owner`.
3. Click `Query`.

`maxWithdraw(owner)` returns the maximum amount of underlying asset that can currently be withdrawn by that wallet.
This value already accounts for your SuperPool share balance and the liquidity available across the SuperPool and
its underlying pools.

If the returned value is:

- `0`: there is currently no withdrawable liquidity for your wallet, or the SuperPool is paused.
- Less than your expected full balance: only a partial withdrawal is currently available.
- Greater than `0`: you can withdraw up to that amount.

Do not submit a withdrawal for more than `maxWithdraw(owner)`. A larger withdrawal is expected to revert,
commonly because the SuperPool does not have enough available liquidity.

Optional checks:

- `decimals()` returns the number of decimals to use when converting between display amounts and raw units.
- `convertToAssets(balanceOfResult)` estimates the underlying asset value of all your SuperPool shares.
- `previewWithdraw(assets)` estimates how many SuperPool shares will be burned for a specific withdrawal amount.
- `asset()` returns the underlying token contract address that the withdrawal will send to your wallet.

## Step 3: Connect Your Wallet

1. Open the `Contract` tab.
2. Open `Write Contract`.
3. Click `Connect to Web3`.
4. Connect the wallet that owns the SuperPool shares.
5. Confirm your wallet is connected to HyperEVM mainnet, chain ID `999`.

## Step 4: Withdraw

On the SuperPool `Write Contract` page:

1. Find the `withdraw` function.
2. Fill the fields:

| Field | Value |
| --- | --- |
| `assets` | The amount of underlying asset to withdraw, in raw token units. This must be less than or equal to `maxWithdraw(owner)`. |
| `receiver` | The wallet address that should receive the withdrawn asset. Usually this is your own wallet address. |
| `owner` | The wallet address that owns the SuperPool shares. Usually this is your own wallet address. |

3. Click `Write`.
4. Review the transaction in your wallet.
5. Confirm the transaction.
6. Wait for the transaction to be included on HyperEVM.

For a normal self-withdrawal, `receiver` and `owner` should both be your connected wallet address.

After the transaction confirms, the SuperPool shares burned by the withdrawal should decrease and the
underlying asset should appear in the `receiver` wallet. The HYPE SuperPool withdraws its underlying
token as the SuperPool asset. If that asset is wrapped HYPE, unwrap it separately only if you need native HYPE.

## If the Transaction Fails

Common causes:

- The `assets` amount was higher than `maxWithdraw(owner)`.
- The value was entered in display units instead of raw token units.
- The wallet connected to HyperEVMScan is not the `owner` address.
- The SuperPool has insufficient available liquidity.
- The SuperPool is paused, in which case `maxWithdraw(owner)` should return `0`.

If liquidity is the issue, repeat Step 2 later and withdraw up to the latest `maxWithdraw(owner)`
value when liquidity becomes available.

## Alternative: Redeem Shares

The contract also exposes `redeem(shares, receiver, owner)`, which withdraws by specifying the number of
SuperPool shares to burn instead of the exact amount of underlying asset to receive.
Most users should use `withdraw(assets, receiver, owner)` because `maxWithdraw(owner)` directly reports
the maximum underlying asset amount currently available.

If you use `redeem`, check `maxRedeem(owner)` first and do not redeem more shares than that value.

## Support
If you face any issues during this process and fail to withdraw your assets, reach out to @ruvaag on telegram
