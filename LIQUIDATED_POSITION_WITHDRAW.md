# Withdrawing Free Collateral from Liquidated Sentiment V2 Positions on HyperEVM

The Sentiment V2 protocol and user interface have been deprecated. If one of your
positions was liquidated, the liquidation repaid the position's debt, but any
remaining collateral stayed in the position contract. You can withdraw that free
collateral directly through HyperEVMScan.

This guide is for HyperEVM mainnet, chain ID `999`, using HyperEVMScan:
<https://hyperevmscan.io>.

## Before You Start

You need:

- The wallet that owns, or is authorized for, the Sentiment position.
- A small amount of native HYPE in that wallet for gas.
- The correct network selected in your wallet: HyperEVM mainnet, chain ID `999`.
- The position address that holds the remaining asset.
- The ERC-20 asset address to withdraw from that position.

The Position Manager contract is:

[`0xE019Ce6e80dFe505bca229752A1ad727E14085a4`](https://hyperevmscan.io/address/0xE019Ce6e80dFe505bca229752A1ad727E14085a4)

## Step 1: Find Your Position Addresses

1. Open the Dune query:
   <https://dune.com/queries/7607694>
2. Enter your wallet address in the `owner` field.
3. Run the query.
4. Review the results and copy the addresses shown in the `position` column.

Each `position` address is a Sentiment position contract that may still hold
free collateral after liquidation.

## Step 2: Check Which Positions Still Hold Assets

For each position address from the Dune query:

1. Open <https://hyperevmscan.io>.
2. Paste the position address into the search bar.
3. Open the position address page.
4. Check the token holdings shown by HyperEVMScan.

If a position has no token balances, there is nothing to withdraw from that
position.

If a position has token balances, note:

- The position address.
- Each ERC-20 asset address held by the position.

You do not need to calculate the token amount. The Position Manager supports
using `uint256.max` as the transfer amount, which withdraws the full token
balance from the position.

## Step 3: Open the Position Manager Write Page

1. Open the Position Manager on HyperEVMScan:
   <https://hyperevmscan.io/address/0xE019Ce6e80dFe505bca229752A1ad727E14085a4>
2. Open `Contract` -> `Write Contract`.
3. Click `Connect to Web3`.
4. Connect the wallet that owns, or is authorized for, the position.
5. Find the `process` function.

Use `process`, not a token contract transfer. The assets are held by the
position contract, and only the Position Manager can instruct the position to
send them out.

## Step 4: Fill the `process` Call

The `process` function has this shape:

```text
process(address position, (uint8 op, bytes data) action)
```

Fill the fields as follows:

| Field | Value |
| --- | --- |
| `position` | The position address that holds the asset. |
| `action.op` | `3` |
| `action.data` | Packed transfer data described below. |

`op = 3` means `Operation.Transfer`.

### Transfer Data

The transfer action data is a single packed `0x...` hex string:

```text
0x + recipient wallet without 0x + asset address without 0x + uint256.max as 32-byte hex
```

Use this `uint256.max` value:

```text
ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
```

So the full `action.data` format is:

```text
0x<yourWalletAddressWithout0x><assetAddressWithout0x>ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
```

Example template:

```text
position:
<POSITION_ADDRESS>

action:
(3, 0x<YOUR_WALLET_WITHOUT_0X><ASSET_WITHOUT_0X>ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
```

If HyperEVMScan displays the tuple fields separately, enter:

```text
op:
3

data:
0x<YOUR_WALLET_WITHOUT_0X><ASSET_WITHOUT_0X>ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
```

Replace:

- `<POSITION_ADDRESS>` with the position address from the Dune query.
- `<YOUR_WALLET_WITHOUT_0X>` with the wallet that should receive the asset,
  removing the leading `0x`.
- `<ASSET_WITHOUT_0X>` with the ERC-20 asset contract address to withdraw,
  removing the leading `0x`.

For example, if your wallet is:

```text
0x1111111111111111111111111111111111111111
```

and the asset is:

```text
0x2222222222222222222222222222222222222222
```

then `action.data` is:

```text
0x11111111111111111111111111111111111111112222222222222222222222222222222222222222ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
```

## Step 5: Submit the Transaction

1. Click `Write` on the `process` function.
2. Review the transaction in your wallet.
3. Confirm the transaction.
4. Wait for the transaction to be included on HyperEVM.
5. Check your wallet balance for the withdrawn asset.

If the position holds multiple assets, repeat the same `process` call once for
each asset address.

## If the Transaction Fails

Common causes:

- The connected wallet is not the position owner and is not authorized for the
  position.
- The asset address was entered incorrectly.
- The `action.data` value is not packed correctly.
- The asset is not recognized by the Position Manager.
- The position does not actually hold a balance of that asset.

Make sure the `action.data` string has this exact length and order:

```text
0x
+ 40 hex characters for the recipient wallet
+ 40 hex characters for the asset address
+ 64 hex characters for uint256.max
```

That is `146` total characters including the leading `0x`.

## Support

If you face any issues during this process and fail to withdraw your assets,
reach out to @ruvaag on Telegram.
