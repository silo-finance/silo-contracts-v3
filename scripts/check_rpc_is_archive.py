#!/usr/bin/env python3
"""Check whether RPC_URL is an archive node for ARCHIVE_BLOCK.

Same checks as silo-core/test/foundry/rpc/ArchiveRpc.t.sol:
latest header, historical state, then block body and receipts.
A response without an RPC error counts as success. The balance value is ignored.

    RPC_URL=$RPC_BASE python3 scripts/check_rpc_is_archive.py
    RPC_URL=https://ethereum.publicnode.com python3 scripts/check_rpc_is_archive.py
    RPC_URL=https://rpc.pharos.xyz python3 scripts/check_rpc_is_archive.py 15091991
    RPC_URL=https://ethereum.publicnode.com python3 scripts/check_rpc_is_archive.py 16000000
"""

from __future__ import annotations

import json
import os
import sys
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ARCHIVE_BLOCK = 15_091_991
PROBE = "0x0000000000000000000000000000000000000001"
PREVIEW_LINES = 30


class RpcError(Exception):
    def __init__(self, error: Any) -> None:
        if isinstance(error, dict):
            message = error.get("message", error)
        else:
            message = error
        super().__init__(str(message))


def rpc(url: str, method: str, params: list[Any]) -> Any:
    payload = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    request = Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "User-Agent": "silo-check-rpc-is-archive"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=60) as response:
            body = json.loads(response.read().decode())
    except HTTPError as error:
        raw = error.read().decode(errors="replace")
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            raise RpcError(f"HTTP {error.code}: {raw[:300]}") from error
    except URLError as error:
        raise RpcError(error.reason) from error

    if body.get("error") is not None:
        raise RpcError(body["error"])
    return body.get("result")


def print_preview(title: str, value: Any) -> None:
    lines = json.dumps(value, indent=2).splitlines()
    print(f"\n{title} ({len(lines)} lines, showing {min(PREVIEW_LINES, len(lines))})")
    print("\n".join(lines[:PREVIEW_LINES]))


def main() -> None:
    url = os.environ.get("RPC_URL", "").strip()
    if not url:
        sys.exit("RPC_URL is not set")

    block = int(sys.argv[1]) if len(sys.argv) > 1 else ARCHIVE_BLOCK
    quantity = hex(block)

    latest = rpc(url, "eth_getBlockByNumber", ["latest", False])
    print(f"block {int(latest['number'], 16)}")
    print(f"timestamp {int(latest['timestamp'], 16)}")

    try:
        rpc(url, "eth_getBalance", [PROBE, quantity])
    except RpcError as error:
        sys.exit(f"RPC is not archive: block {block} was not served ({error})")

    print(f"block {block} ({quantity}): historical state is available")

    try:
        block_body = rpc(url, "eth_getBlockByNumber", [quantity, True])
        receipts = rpc(url, "eth_getBlockReceipts", [quantity])
    except RpcError as error:
        sys.exit(
            f"RPC state is archive, but block {block} transactions or receipts were not served ({error})"
        )

    print_preview("eth_getBlockByNumber", block_body)
    print_preview("eth_getBlockReceipts", receipts)
    print(f"\nblock {block} transactions and receipts were served")


if __name__ == "__main__":
    main()
