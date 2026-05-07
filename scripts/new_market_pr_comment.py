#!/usr/bin/env python3
"""
Generate (and optionally post) a PR comment for a newly deployed market.
Content is formatted for use in Slack: new market notice with explorer link,
verification comment link, simulation (new market tests) comment link, and Silo Market Crafter view link.

Usage:
  # Generate comment body (print to stdout; copy to Slack or use with sticky comment)
  python3 scripts/new_market_pr_comment.py --market-name "Silo_hgETH_WETH_id_184" \\
    --address 0xaE01a8BdA7799A7aE4D56CC255db56a7e7FaF7F8 --chain mainnet

  # Post as a sticky comment on the current PR (requires GITHUB_REPOSITORY, GITHUB_EVENT_PATH, gh auth)
  python3 scripts/new_market_pr_comment.py --market-name "Silo_hgETH_WETH_id_184" \\
    --address 0xaE01a8BdA7799A7aE4D56CC255db56a7e7FaF7F8 --chain mainnet --post

  # With explicit PR (e.g. when not in GitHub Actions)
  python3 scripts/new_market_pr_comment.py --market-name "Silo_hgETH_WETH_id_184" \\
    --address 0xaE01a8BdA7799A7aE4D56CC255db56a7e7FaF7F8 --chain mainnet --post --pr 123

  # Output to file for use with marocchino/sticky-pull-request-comment
  python3 scripts/new_market_pr_comment.py --market-name "Silo_hgETH_WETH_id_184" \\
    --address 0xaE01a8BdA7799A7aE4D56CC255db56a7e7FaF7F8 --chain mainnet -o new_market_comment.md

  # CI: detect new markets from _siloDeployments.json diff and write comment body to file
  python3 scripts/new_market_pr_comment.py --from-diff --base $BASE_SHA --head $HEAD_SHA -o new_market_comment.md
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

# Chain slug -> (display name for "Mainnet" etc., explorer base URL for address)
CHAIN_CONFIG: dict[str, tuple[str, str]] = {
    "mainnet": ("Mainnet", "https://etherscan.io/address/"),
    "arbitrum_one": ("Arbitrum", "https://arbiscan.io/address/"),
    "avalanche": ("Avalanche", "https://avalanche.routescan.io/address/"),
    "base": ("Base", "https://basescan.org/address/"),
    "bnb": ("BNB", "https://bscscan.com/address/"),
    "injective": ("Injective", "https://blockscout.injective.network/address/"),
    "optimism": ("Optimism", "https://optimistic.etherscan.io/address/"),
    "okx": ("OKX", "https://www.oklink.com/x-layer/address/"),
    "sonic": ("Sonic", "https://sonicscan.org/address/"),
    "ink": ("Ink", "https://explorer.inkonchain.com/address/"),
    "xdc": ("XDC", "https://xdcscan.com/address/"),
    "mantle": ("Mantle", "https://mantlescan.xyz/address/"),
    "megaeth": ("MegaETH", "https://mega.etherscan.io/address/"),
}

SILO_MARKET_CRAFTER_BASE = "https://silo-finance.github.io/silo-market-crafter/wizard/?step=13&address="

# EVM chain slug -> numeric chain id for Market Crafter deep link
CHAIN_IDS: dict[str, int] = {
    "mainnet": 1,
    "arbitrum_one": 42161,
    "optimism": 10,
    "avalanche": 43114,
    "base": 8453,
    "bnb": 56,
    "injective": 1776,
    "okx": 196,
    "sonic": 146,
    "ink": 57073,
    "xdc": 50,
    "mantle": 5000,
    "megaeth": 4326,
}

SILO_DEPLOYMENTS_JSON = "silo-core/deploy/silo/_siloDeployments.json"

# Prefer verify-silo (Silo verifier CI) comment; fallback to Explorer verification comment
VERIFICATION_COMMENT_MARKERS_PREFERRED = ("verify-silo",)
VERIFICATION_COMMENT_MARKERS_FALLBACK = (
    "Deployment verification on block explorers",
    "deployment-verification",
)

# Simulation = LIVE MARKET QA (NewMarketTest) comment from verify-silo workflow
SIMULATION_COMMENT_MARKERS = ("live-market-qa", "LIVE MARKET QA")


def normalize_address(addr: str) -> str:
    return addr.strip().lower() if addr else ""


def get_verification_comment_url(repo: str, pr_number: int) -> str | None:
    """Return the HTML URL of the PR comment that contains verification report (prefer verify-silo)."""
    return _get_comment_url_by_markers(
        repo, pr_number,
        VERIFICATION_COMMENT_MARKERS_PREFERRED,
        VERIFICATION_COMMENT_MARKERS_FALLBACK,
    )


def get_simulation_comment_url(repo: str, pr_number: int) -> str | None:
    """Return the HTML URL of the PR comment that contains new market tests (LIVE MARKET QA)."""
    return _get_comment_url_by_markers(
        repo, pr_number,
        SIMULATION_COMMENT_MARKERS,
        (),
    )


def _get_comment_url_by_markers(
    repo: str,
    pr_number: int,
    preferred: tuple[str, ...],
    fallback: tuple[str, ...],
) -> str | None:
    """Return the HTML URL of the first PR comment matching preferred markers, or fallback."""
    try:
        out = subprocess.run(
            ["gh", "api", f"repos/{repo}/issues/{pr_number}/comments"],
            capture_output=True,
            text=True,
            timeout=30,
            env={**os.environ},
        )
        if out.returncode != 0:
            return None
        comments = json.loads(out.stdout)
        fallback_url: str | None = None
        for c in comments:
            body = c.get("body", "")
            if any(m in body for m in preferred):
                return c.get("html_url")
            if fallback_url is None and fallback and any(m in body for m in fallback):
                fallback_url = c.get("html_url")
        return fallback_url
    except Exception:
        pass
    return None


def get_pr_number_from_event() -> int | None:
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path or not Path(event_path).exists():
        return None
    try:
        event = json.loads(Path(event_path).read_text())
        return event.get("pull_request", {}).get("number")
    except Exception:
        return None


def build_comment_body(
    market_name: str,
    address: str,
    chain: str,
    verification_url: str | None = None,
    simulation_url: str | None = None,
) -> str:
    chain_display, explorer_base = CHAIN_CONFIG.get(
        chain, ("Mainnet", "https://etherscan.io/address/")
    )
    addr = normalize_address(address)
    explorer_link = f"{explorer_base}{addr}" if addr else ""
    view_link = f"{SILO_MARKET_CRAFTER_BASE}{addr}" if addr else ""
    # Optional chain id parameter for Market Crafter "Market config tree" link
    chain_id = CHAIN_IDS.get(chain)
    if view_link and chain_id is not None:
        view_link = f"{view_link}&chain={chain_id}"

    lines = [
        f"notify people on slack with this comment when PR will be finalized",
        f"------",
        f"new market on {chain_display}:",
        f'"{market_name}":',
        f"- [{addr}]({explorer_link})" if explorer_link else f"- {addr}",
        "- [PR verification]({})".format(verification_url) if verification_url else "- verification (comment not found)",
        "- [PR simulation]({})".format(simulation_url) if simulation_url else "- simulation (comment not found)",
        "- [Market config tree]({})".format(view_link) if view_link else "- view",
        "ready for production :white_check_mark:",
    ]
    return "\n".join(lines)


def load_silo_deployments_at_ref(repo_root: Path, ref: str) -> dict[str, dict[str, str]]:
    """Load _siloDeployments.json at git ref. Returns {chain: {market_name: address}}."""
    try:
        out = subprocess.run(
            ["git", "show", f"{ref}:{SILO_DEPLOYMENTS_JSON}"],
            cwd=repo_root,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if out.returncode != 0:
            return {}
        return json.loads(out.stdout)
    except Exception:
        return {}


def find_new_markets_from_diff(
    repo_root: Path, base_ref: str, head_ref: str
) -> list[tuple[str, str, str]]:
    """Compare _siloDeployments.json between base and head. Returns [(chain, market_name, address), ...] for new or changed markets."""
    base_data = load_silo_deployments_at_ref(repo_root, base_ref)
    head_data = load_silo_deployments_at_ref(repo_root, head_ref)
    new_markets: list[tuple[str, str, str]] = []
    for chain, markets in head_data.items():
        if chain not in CHAIN_CONFIG:
            continue
        base_markets = base_data.get(chain, {})
        for name, address in markets.items():
            if not address or not name:
                continue
            prev = base_markets.get(name)
            if prev is None or normalize_address(prev) != normalize_address(address):
                new_markets.append((chain, name, address))
    return new_markets


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate PR comment body for a newly deployed market (Slack-style).",
    )
    parser.add_argument("--from-diff", action="store_true", help="Detect new markets from _siloDeployments.json diff (use with --base, --head)")
    parser.add_argument("--base", help="Base git ref for diff (e.g. pull request base SHA)")
    parser.add_argument("--head", default="HEAD", help="Head git ref for diff (default: HEAD)")
    parser.add_argument("--market-name", help="Market name, e.g. Silo_hgETH_WETH_id_184")
    parser.add_argument("--address", help="Deployed market contract address")
    parser.add_argument(
        "--chain",
        choices=list(CHAIN_CONFIG),
        help="Chain slug (mainnet, arbitrum_one, injective, ...)",
    )
    parser.add_argument(
        "--post",
        action="store_true",
        help="Post comment on the current PR (requires gh auth and GITHUB_* env or --repo --pr)",
    )
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"), help="GitHub repo (owner/repo)")
    parser.add_argument("--pr", type=int, help="PR number (default: from GITHUB_EVENT_PATH)")
    parser.add_argument("-o", "--output", metavar="FILE", help="Write comment body to file")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent

    if args.from_diff:
        if not args.base:
            print("--from-diff requires --base.", file=sys.stderr)
            return 1
        new_markets = find_new_markets_from_diff(repo_root, args.base, args.head)
        if not new_markets:
            if args.output:
                Path(args.output).write_text("", encoding="utf-8")
            return 0
        pr_number = args.pr or get_pr_number_from_event()
        verification_url: str | None = None
        simulation_url: str | None = None
        if args.repo and pr_number is not None:
            verification_url = get_verification_comment_url(args.repo, pr_number)
            simulation_url = get_simulation_comment_url(args.repo, pr_number)
        blocks = [
            build_comment_body(name, addr, chain, verification_url, simulation_url)
            for chain, name, addr in new_markets
        ]
        body = "\n\n---\n\n".join(blocks)
        if args.output:
            Path(args.output).write_text(body, encoding="utf-8")
            return 0
        print(body)
        return 0

    if not args.market_name or not args.address or not args.chain:
        print("Either --from-diff with --base, or --market-name, --address, and --chain are required.", file=sys.stderr)
        return 1

    pr_number = args.pr
    if pr_number is None:
        pr_number = get_pr_number_from_event()
    if args.post and pr_number is None:
        print("Cannot post: PR number not set. Use --pr or run in a PR context (GITHUB_EVENT_PATH).", file=sys.stderr)
        return 1

    verification_url = None
    simulation_url = None
    if args.repo and pr_number is not None:
        verification_url = get_verification_comment_url(args.repo, pr_number)
        simulation_url = get_simulation_comment_url(args.repo, pr_number)

    body = build_comment_body(
        args.market_name,
        args.address,
        args.chain,
        verification_url,
        simulation_url,
    )

    if args.output:
        Path(args.output).write_text(body, encoding="utf-8")
        print(f"Wrote comment to {args.output}", file=sys.stderr)
        return 0

    if args.post:
        if not args.repo:
            print("Cannot post: --repo or GITHUB_REPOSITORY required.", file=sys.stderr)
            return 1
        # Write to temp file and let gh pr comment read it (or we could use gh api to create comment)
        comment_file = Path("new_market_comment.md")
        comment_file.write_text(body, encoding="utf-8")
        out = subprocess.run(
            ["gh", "pr", "comment", str(pr_number), "--body-file", str(comment_file)],
            env=os.environ,
            capture_output=True,
            text=True,
        )
        comment_file.unlink(missing_ok=True)
        if out.returncode != 0:
            print(out.stderr, file=sys.stderr)
            return 1
        print("Comment posted.", file=sys.stderr)
        return 0

    print(body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
