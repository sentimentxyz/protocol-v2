#!/usr/bin/env python3
"""
SV2 Deprecation — aggregate baseline snapshot.

Captures pool-level aggregates at the moment of running, to be re-run daily
during deprecation so we can measure voluntary-exit rate (= debt paid down).

Intentionally aggregate-only: per-position enumeration requires multicall3
batching due to HL public RPC rate limits and 4k+ historical borrowers per pool.
For prioritizing individual liquidations in Phase 2+, use a separate
multicall3-based script.

Usage:
    python3 sv2_baseline_snapshot.py [output_dir]
"""

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

RPC = "https://rpc.hyperliquid.xyz/evm"
POOL = "0x36BFD6b40e2c9BbCfD36a6B1F1Aa65974f4fFA5D"
REGISTRY = "0x121430beCc13238ef81e40A968d019Fc8dFB2605"
RISK_ENGINE = "0xd22dE451Ba71fA6F06C65962649ba4E2Aea10863"
WSTHYPE = "0x94e8396e0869c9F2200760aF0621aFd240E1CF38"

POOLS = [
    ("HYPE",  14778331100793740007929971613900703995604470186100539494274894855699577891585, 18),
    ("USDT0", 24340067792848736884157565898336136257613434225645880261054440301452940585526, 6),
    ("USDe",  35549059506791825930759374493305863417254935666006142339056302529054626325948, 18),
]


def cast_call(target: str, sig: str, *args: str, retries: int = 6) -> str:
    cmd = ["cast", "call", target, sig, *args, "--rpc-url", RPC]
    last = None
    for attempt in range(retries):
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=30)
            return res.stdout.strip()
        except Exception as e:
            last = e
            time.sleep(1 * (2 ** attempt))
    raise RuntimeError(f"cast call failed: {last}")


def cast_parts(target: str, sig: str, *args: str) -> list[str]:
    return [ln.split()[0] for ln in cast_call(target, sig, *args).splitlines() if ln.strip()]


def current_block() -> int:
    for attempt in range(6):
        try:
            r = subprocess.run(["cast", "block-number", "--rpc-url", RPC], capture_output=True, text=True, check=True, timeout=30)
            return int(r.stdout.strip())
        except Exception:
            time.sleep(1 * (2 ** attempt))
    raise RuntimeError("block-number failed")


def query_pool(poolid: int) -> dict:
    parts = cast_parts(
        POOL,
        "poolDataFor(uint256)(bool,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256)",
        str(poolid),
    )
    ltv = cast_parts(RISK_ENGINE, "ltvFor(uint256,address)(uint256)", str(poolid), WSTHYPE)[0]
    total_borrow = cast_parts(POOL, "getTotalBorrows(uint256)(uint256)", str(poolid))[0]
    total_deposit = cast_parts(POOL, "getTotalAssets(uint256)(uint256)", str(poolid))[0]
    liquidity = cast_parts(POOL, "getLiquidityOf(uint256)(uint256)", str(poolid))[0]
    return {
        "isPaused": parts[0] == "true",
        "asset": parts[1],
        "rateModel": parts[2],
        "borrowCap": parts[3],
        "depositCap": parts[4],
        "lastUpdated": parts[5],
        "interestFee": parts[6],
        "originationFee": parts[7],
        "totalBorrowAssets": parts[8],
        "totalBorrowShares": parts[9],
        "totalDepositAssets": parts[10],
        "totalDepositShares": parts[11],
        "totalBorrowAssetsWithInterest": total_borrow,
        "totalDepositAssetsWithInterest": total_deposit,
        "liquidityAvailable": liquidity,
        "ltvWstHype": ltv,
    }


def main():
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "logs"
    out_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_path = out_dir / f"sv2-baseline-{ts}.json"

    block = current_block()
    print(f"Snapshot at block {block}", file=sys.stderr)

    pools_out = {}
    for name, poolid, decimals in POOLS:
        print(f"[{name}] fetching state...", file=sys.stderr)
        state = query_pool(poolid)
        pools_out[name] = {
            "poolId": str(poolid),
            "assetDecimals": decimals,
            "state": state,
        }

    out = {
        "generatedAt": ts,
        "block": str(block),
        "registry": REGISTRY,
        "pool": POOL,
        "riskEngine": RISK_ENGINE,
        "wstHype": WSTHYPE,
        "pools": pools_out,
    }
    out_path.write_text(json.dumps(out, indent=2))

    # Human summary
    print()
    print("=== SV2 Baseline Summary ===")
    print(f"Block: {block}   |   UTC: {ts}")
    for name, poolid, decimals in POOLS:
        p = pools_out[name]
        s = p["state"]
        scale = 10 ** decimals
        borrow_raw = int(s["totalBorrowAssetsWithInterest"])
        deposit_raw = int(s["totalDepositAssetsWithInterest"])
        borrow = borrow_raw / scale
        deposit = deposit_raw / scale
        liq = int(s["liquidityAvailable"]) / scale
        util = borrow / deposit if deposit else 0.0
        ltv_pct = int(s["ltvWstHype"]) / 1e16
        print()
        print(f"{name} pool")
        print(f"  rateModel      : {s['rateModel']}")
        print(f"  wstHYPE LTV    : {ltv_pct:.1f}%")
        print(f"  totalBorrows   : {borrow:,.4f} {name}")
        print(f"  totalDeposits  : {deposit:,.4f} {name}")
        print(f"  liquidity avail: {liq:,.4f} {name}")
        print(f"  utilization    : {util*100:.2f}%")

    print()
    print(f"✅ Snapshot written to {out_path}")
    return str(out_path)


if __name__ == "__main__":
    main()
