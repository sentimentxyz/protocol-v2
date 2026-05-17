# Repaying Sentiment V2 Position Debt and Withdrawing Collateral on HyperEVM

The Sentiment V2 interface has been deprecated after the protocol was wound down.
If you still have an open Sentiment V2 debt position on HyperEVM, you can repay the
debt and withdraw the assets held by the position directly through HyperEVMScan.

This guide is for HyperEVM mainnet, chain ID `999`, using HyperEVMScan: <https://hyperevmscan.io>.

## Assumptions

This guide assumes:

- You control the wallet that owns, or is authorized for, the Sentiment position.
- You want to repay the full debt in one transaction.
- You will source the required debt asset yourself before repaying.
- You will approve and deposit enough of the debt asset into the position, then use `uint256.max` for the repay amount
so the contract repays the full current debt.
- You want to withdraw all remaining known assets from the position after repayment.

The repayment amount accrues over time. To avoid a transaction failing because the debt increased after you checked it,
deposit slightly more debt asset than the current debt shown by the contract. The extra amount can be transferred back to
your wallet in the same batch after the debt is repaid.

## Contract Addresses

Use these HyperEVM mainnet contracts:

Deployment source: <https://docs.sentiment.xyz/contracts/v2/Deployments>

| Contract | Address |
| --- | --- |
| Position Manager | [`0xE019Ce6e80dFe505bca229752A1ad727E14085a4`](https://hyperevmscan.io/address/0xE019Ce6e80dFe505bca229752A1ad727E14085a4) |
| Pool | [`0x36BFD6b40e2c9BbCfD36a6B1F1Aa65974f4fFA5D`](https://hyperevmscan.io/address/0x36BFD6b40e2c9BbCfD36a6B1F1Aa65974f4fFA5D) |
| Portfolio Lens | [`0x9700750001dDD7C4542684baC66C64D74fA833c0`](https://hyperevmscan.io/address/0x9700750001dDD7C4542684baC66C64D74fA833c0) |

Supported asset addresses:

| Asset | Address |
| --- | --- |
| wHYPE | [`0x5555555555555555555555555555555555555555`](https://hyperevmscan.io/address/0x5555555555555555555555555555555555555555) |
| wstHYPE | [`0x94e8396e0869c9F2200760aF0621aFd240E1CF38`](https://hyperevmscan.io/address/0x94e8396e0869c9F2200760aF0621aFd240E1CF38) |
| USDT0 | [`0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb`](https://hyperevmscan.io/address/0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb) |
| USDe | [`0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34`](https://hyperevmscan.io/address/0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34) |

Base pool IDs:

| Debt Asset | Pool ID | Pool ID as 32-byte hex |
| --- | --- | --- |
| HYPE / wHYPE | `14778331100793740007929971613900703995604470186100539494274894855699577891585` | `0x20ac3d2e28db1ed11b103cb2701b6a27ca05b5fd9668ea574424b48c5f5aeb01` |
| USDT0 | `24340067792848736884157565898336136257613434225645880261054440301452940585526` | `0x35cffd7ba761a0d9e452dad3e5d572c65b5112fa81eb503fe432cc6c30d4aa36` |
| USDe | `35549059506791825930759374493305863417254935666006142339056302529054626325948` | `0x4e980dfdbcc9c794e9898ca904d9ff6185604d196e94a6e38329f7722cfca5bc` |

## Step 1: Find Your Position Address

If you already know your position address, skip to Step 2.

1. Open the Position Manager contract on HyperEVMScan:
   <https://hyperevmscan.io/address/0xE019Ce6e80dFe505bca229752A1ad727E14085a4>
2. Open the `Events` tab.
3. Search for `PositionDeployed` events involving your wallet address.
4. In the matching event, copy the `position` address.

The `PositionDeployed` event contains:

- `position`: the Sentiment position contract address.
- `caller`: the wallet or contract that created the position.
- `owner`: the owner wallet for the position.

If HyperEVMScan does not make event filtering easy, search your wallet's HyperEVM transaction
history for the transaction that created the Sentiment position, then open the transaction
logs and find the `PositionDeployed` event emitted by the Position Manager.

The `owner` field is indexed in the event. If HyperEVMScan shows raw event topics, your owner
address appears as the last 20 bytes of one of the topics, left-padded with zeroes.

## Step 2: Confirm Position Ownership and Current Debt

1. Open the Portfolio Lens contract:
   <https://hyperevmscan.io/address/0x9700750001dDD7C4542684baC66C64D74fA833c0>
2. Open `Contract` -> `Read Contract`.
3. Find `getPositionData`.
4. Enter your position address.
5. Click `Query`.

Review the returned data:

- `owner` should be your wallet address.
- `assets` lists the assets currently held by the position. These are the assets you can withdraw after repaying the debt.
- `debts` lists each active debt. Each debt includes `poolId`, `asset`, and `amount`.

If `debts` is empty, the position has no active debt. You can skip repayment and only submit transfer
actions for the assets still held by the position.

You can also check the debt directly on the Pool contract:

1. Open the Pool contract:
   <https://hyperevmscan.io/address/0x36BFD6b40e2c9BbCfD36a6B1F1Aa65974f4fFA5D>
2. Open `Contract` -> `Read Contract`.
3. Find `getBorrowsOf`.
4. Enter the debt `poolId` and your position address.
5. Click `Query`.

`getBorrowsOf(poolId, position)` returns the current debt amount in raw token units, rounded up so full repayment is possible.

## Step 3: Prepare the Debt Asset

For each debt listed by `getPositionData`:

1. Identify the debt asset from the `asset` field.
2. Make sure your wallet holds at least the current debt amount, plus a small buffer for accrued interest.
3. Open the debt asset token contract on HyperEVMScan.
4. Open `Contract` -> `Write Contract`.
5. Connect the wallet that owns the position.
6. Find `approve`.
7. Approve the Position Manager as spender:

| Field | Value |
| --- | --- |
| `spender` | `0xE019Ce6e80dFe505bca229752A1ad727E14085a4` |
| `amount` | `0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff` |

Amounts are raw token units. Check the token's `decimals()` value on the token contract if you need to convert from display units. For example, a token with `18` decimals represents `1` token as `1000000000000000000`.

If the debt asset is wHYPE and you only have native HYPE, wrap enough HYPE into wHYPE first.
The protocol debt asset is the ERC-20 token shown by the `asset` field, not native HYPE.

## Step 4: Build the PositionManager Batch

The Position Manager `processBatch` function accepts an array of actions. Each action is a tuple:

```text
(op, data)
```

Use these operation numbers:

| Operation | `op` |
| --- | ---: |
| Deposit | `2` |
| Transfer | `3` |
| Repay | `5` |

Use this max uint256 value for full repayment and full transfers:

```text
0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
```

If HyperEVMScan asks for this value in a normal `uint256` amount field, use the decimal form:

```text
115792089237316195423570985008687907853269984665640564039457584007913129639935
```

Build the actions in this order:

1. Deposit the debt asset from your wallet into the position.
2. Repay the debt using `uint256.max`.
3. Transfer each remaining asset from the position back to your wallet using `uint256.max`.

### Action Data Format

The `data` field is packed bytes. It must be entered as one continuous `0x...` hex string.

Deposit action data:

```text
0x + asset address without 0x + deposit amount as 32-byte hex
```

Repay action data:

```text
0x + poolId as 32-byte hex + ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
```

Transfer action data:

```text
0x + recipient wallet without 0x + asset address without 0x + ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
```

The `uint256.max` transfer amount means "transfer the full balance of this asset from the position."
After the repay action, include transfer actions for every asset returned by `getPositionData.assets`,
and include the debt asset too if you deposited a buffer.

To convert a raw decimal amount into the 32-byte hex required for `data`, convert the decimal amount to hex
and left-pad it with zeroes until it is 64 hex characters. For example, raw amount `1000000` becomes:

```text
00000000000000000000000000000000000000000000000000000000000f4240
```

When using one of the base pool IDs from the table above, use the 32-byte hex form without the leading `0x` inside
the repay action data.

## Step 5: Submit the Batch

1. Open the Position Manager contract:
   <https://hyperevmscan.io/address/0xE019Ce6e80dFe505bca229752A1ad727E14085a4>
2. Open `Contract` -> `Write Contract`.
3. Click `Connect to Web3`.
4. Connect the wallet that owns, or is authorized for, the position.
5. Find `processBatch`.
6. Enter your position address in the `position` field.
7. Enter the actions array.
8. Click `Write`.
9. Review the transaction in your wallet and confirm it.

The action array should look conceptually like this:

```text
[
  (2, 0x<debtAsset><depositAmount32Bytes>),
  (5, 0x<poolId32Bytes>ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff),
  (3, 0x<yourWallet><collateralAsset>ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff),
  (3, 0x<yourWallet><debtAsset>ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
]
```

HyperEVMScan may render tuple-array inputs with separate `op` and `data` fields instead of a single text box.
If so, add one tuple per action and paste the same `op` and `data` values into the displayed fields.

## Step 6: Verify Repayment and Withdrawal

After the transaction confirms:

1. Query `getPositionData(position)` again on the Portfolio Lens.
2. Confirm `debts` is empty.
3. Confirm the transferred assets arrived in your wallet.
4. If an asset still appears in `assets` with a non-zero `amount`, submit another `Transfer` action for that asset using `uint256.max`.

## If the Transaction Fails

Common causes:

- The connected wallet is not the position owner and is not authorized for the position.
- The debt asset approval was missing or too low.
- The deposit amount was too low because debt accrued after you checked it.
- The `data` bytes were formatted incorrectly.
- The position includes multiple debt pools but the batch repaid only one of them.
- A transfer action used an asset that is not a known Sentiment asset.

If the transaction fails because the deposit was too small, query `getBorrowsOf(poolId, position)` again,
increase the deposit amount, keep `uint256.max` as the repay amount, and retry the batch.

## Notes on Multiple Debts

Some positions may have more than one active debt. In that case, include a deposit and repay action for each
debt before the transfer actions:

```text
[
  (2, 0x<debtAssetA><depositAmountA32Bytes>),
  (5, 0x<poolIdA32Bytes>ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff),
  (2, 0x<debtAssetB><depositAmountB32Bytes>),
  (5, 0x<poolIdB32Bytes>ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff),
  (3, 0x<yourWallet><assetToWithdraw1>ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff),
  (3, 0x<yourWallet><assetToWithdraw2>ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
]
```

Approve each debt asset before submitting the batch.

## Support

If you face any issues during this process and fail to withdraw your assets, reach out to @ruvaag on Telegram.
