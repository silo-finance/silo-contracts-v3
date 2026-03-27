#!/usr/bin/env python3
"""
Merge per-chain verification JSON artifacts into a single PR comment.

Used by CI when verification runs in separate jobs per chain. Each job uploads
a JSON artifact; this script merges them and optionally with the existing
PR comment (for re-run of failed jobs).

Usage:
  # Merge artifacts from directory, output to stdout
  python3 scripts/merge_verification_reports.py --artifacts-dir ./artifacts

  # Merge with existing PR comment (fetch via gh CLI)
  python3 scripts/merge_verification_reports.py --artifacts-dir ./artifacts --pr-comment-from-gh

  # Output to file
  python3 scripts/merge_verification_reports.py --artifacts-dir ./artifacts -o report.md
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


# Must match summary_key values from check_deployments_verified_on_explorer.py.
SECTION_ORDER = [
    "arbitrum_one",
    "avalanche routescan",
    "avalanche etherscan",
    "base",
    "bnb",
    "injective blockscout",
    "injective cloud",
    "mainnet",
    "optimism",
    "okx",
    "sonic",
    "xdc",
]

# Block explorer address URL (append address). summary_key -> base URL.
EXPLORER_ADDRESS_URL: dict[str, str] = {
    "arbitrum_one": "https://arbiscan.io/address/",
    "avalanche routescan": "https://snowscan.xyz/address/",
    "avalanche etherscan": "https://snowtrace.io/address/",
    "base": "https://basescan.org/address/",
    "bnb": "https://bscscan.com/address/",
    "injective blockscout": "https://blockscout.injective.network/address/",
    "injective cloud": "https://injective.cloud.blockscout.com/address/",
    "mainnet": "https://etherscan.io/address/",
    "optimism": "https://optimistic.etherscan.io/address/",
    "okx": "https://www.oklink.com/x-layer/address/",
    "sonic": "https://sonicscan.org/address/",
    "xdc": "https://xdcscan.com/address/",
}

# Backward-compat mapping for sections parsed from existing PR comments.
# Existing comments use human display labels, while artifacts now use summary_key.
DISPLAY_LABEL_TO_SUMMARY_KEY: dict[str, str] = {
    "Arbitrum": "arbitrum_one",
    "Avalanche (routescan)": "avalanche routescan",
    "Avalanche (etherscan)": "avalanche etherscan",
    "Base": "base",
    "BNB": "bnb",
    "Injective": "injective blockscout",
    "Injective (blockscout)": "injective blockscout",
    "Injective (cloud)": "injective cloud",
    "Mainnet": "mainnet",
    "Optimism": "optimism",
    "OKX": "okx",
    "Sonic": "sonic",
    "XDC": "xdc",
}


def normalize_section_key(section_key_or_label: str) -> str:
    """Normalize summary keys/display labels to stable summary_key values."""
    raw = str(section_key_or_label).strip()
    if not raw:
        return raw

    # Already a summary_key?
    lower = raw.lower()
    if lower in SECTION_ORDER:
        return lower

    # Exact known display labels
    mapped = DISPLAY_LABEL_TO_SUMMARY_KEY.get(raw)
    if mapped:
        return mapped

    # Fuzzy fallback for legacy/manual variants
    if lower.startswith("injective"):
        return "injective cloud" if "cloud" in lower else "injective blockscout"
    if lower.startswith("avalanche"):
        if "route" in lower:
            return "avalanche routescan"
        if "ether" in lower or "snowtrace" in lower:
            return "avalanche etherscan"

    return raw


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Merge verification JSON artifacts into PR comment.")
    p.add_argument(
        "--artifacts-dir",
        required=True,
        help="Directory containing verification_<chain>.json files.",
    )
    p.add_argument(
        "--pr-comment-from-gh",
        action="store_true",
        help="Fetch existing PR comment via gh CLI and merge (for re-run of failed jobs).",
    )
    p.add_argument(
        "-o", "--output",
        metavar="FILE",
        help="Write output to file (default: stdout).",
    )
    return p.parse_args()


def load_artifacts(artifacts_dir: Path) -> dict[str, dict]:
    """Load all verification_*.json files (searches recursively). Returns {section_key: section_data}."""
    result: dict[str, dict] = {}
    for jf in artifacts_dir.glob("**/verification_*.json"):
        try:
            data = json.loads(jf.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        sections = data.get("sections", [])
        for s in sections:
            summary_key = s.get("summary_key")
            label = s.get("display_label")
            key = normalize_section_key(str(summary_key or label or ""))
            if key:
                result[str(key)] = s
    return result


def parse_existing_comment(body: str) -> dict[str, dict]:
    """
    Parse existing PR comment markdown to extract per-section data.
    Returns {section_key: section_data}. For backward compatibility, display
    labels are normalized to summary_key values when possible.
    """
    result: dict[str, dict] = {}
    # Match ### Section ... until next ### or end
    pattern = re.compile(r"^### (.+?)$\s*\n(.*?)(?=^### |\Z)", re.MULTILINE | re.DOTALL)
    for m in pattern.finditer(body):
        label = m.group(1).strip()
        content = m.group(2).strip()
        section_key = normalize_section_key(label)
        result[section_key] = {"display_label": label, "_raw": content}
    return result


def fetch_pr_comment() -> str | None:
    """Fetch existing sticky comment body via gh CLI. Returns None if not found."""
    import os

    try:
        repo = os.environ.get("GITHUB_REPOSITORY", "")
        event_path = os.environ.get("GITHUB_EVENT_PATH", "")
        if not repo:
            return None

        pr_num = None
        if event_path and Path(event_path).exists():
            event = json.loads(Path(event_path).read_text())
            pr_num = event.get("pull_request", {}).get("number")
        if pr_num is None:
            return None

        out = subprocess.run(
            ["gh", "api", f"repos/{repo}/issues/{pr_num}/comments"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if out.returncode != 0:
            return None

        comments = json.loads(out.stdout)
        for c in comments:
            body = c.get("body", "")
            if "## Deployment verification on block explorers" in body or "deployment-verification" in body:
                body = re.sub(r"<!-- UNVERIFIED_CONTRACTS_REPORT -->\s*", "", body)
                body = re.sub(r"\s*<!-- /UNVERIFIED_CONTRACTS_REPORT -->", "", body)
                return body.strip()
    except Exception:
        pass
    return None


def _format_address_link(section_key: str, address: str) -> str:
    """Format address as markdown link to block explorer, or plain text if no URL."""
    base_url = EXPLORER_ADDRESS_URL.get(section_key)
    if base_url and address:
        return f"[`{address}`]({base_url}{address})"
    return f"`{address}`"


def section_to_markdown(s: dict) -> str:
    """Convert section data to markdown. When all verified, returns single line only."""
    label = s.get("display_label", "Unknown")
    section_key = normalize_section_key(str(s.get("summary_key") or label))
    config_error = s.get("config_error")
    nv = s.get("not_verified", 0)
    fe = s.get("fetch_errors", 0)
    verified = s.get("verified", 0)

    if config_error is None and nv == 0 and fe == 0:
        return f"**{label}: all {verified} contracts verified.**"

    lines = [f"### {label}", ""]
    if config_error:
        lines.append(f"⚠️ **Could not check:** {config_error}")
    else:
        lines.append(f"- **Verified:** {verified}")
        lines.append(f"- **Not verified:** {nv}")
        lines.append(f"- **Errors (could not check):** {fe}")
        lines.append("")
        unverified = s.get("unverified", [])
        errors_list = s.get("errors", [])
        if unverified:
            lines.append("**Unverified contracts:**")
            lines.append("")
            for u in unverified:
                path_display = u.get("source_path") or f"{u.get('component', '')}/{u.get('contract_name', '')}"
                addr = u.get("address", "")
                addr_link = _format_address_link(section_key, addr)
                lines.append(f"- `{path_display}` {addr_link}")
            lines.append("")
        if errors_list:
            lines.append("**Errors (could not check):**")
            lines.append("")
            for u in errors_list:
                path_display = u.get("source_path") or f"{u.get('component', '')}/{u.get('contract_name', '')}"
                addr = u.get("address", "")
                addr_link = _format_address_link(section_key, addr)
                lines.append(f"- `{path_display}` {addr_link}")
            lines.append("")
    lines.append("")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    artifacts_dir = Path(args.artifacts_dir)
    if not artifacts_dir.exists():
        print("Artifacts directory does not exist.", file=sys.stderr)
        return 1

    # Start with existing comment sections (for re-run)
    merged: dict[str, dict] = {}
    existing_body: str | None = None
    if args.pr_comment_from_gh:
        existing_body = fetch_pr_comment()
        if existing_body:
            merged = parse_existing_comment(existing_body)

    # Override with new artifacts
    artifacts = load_artifacts(artifacts_dir)
    for section_key, data in artifacts.items():
        if "_raw" not in data:
            merged[section_key] = data

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    # If we have existing body but no sections, use it as-is when no artifacts
    if not merged and existing_body and not artifacts:
        content = existing_body
        if not content.strip().startswith("##"):
            content = "## Deployment verification on block explorers\n\n" + content
        body = (
            "<!-- UNVERIFIED_CONTRACTS_REPORT -->\n"
            f"{timestamp}\n\n"
            f"{content}\n"
            "<!-- /UNVERIFIED_CONTRACTS_REPORT -->"
        )
        if args.output:
            Path(args.output).write_text(body, encoding="utf-8")
        else:
            print(body)
        return 0

    if not merged:
        content = (
            f"{timestamp}\n\n"
            "## Deployment verification on block explorers\n\n"
            "No verification results (no artifacts and no existing comment)."
        )
    else:
        ordered_section_keys = [x for x in SECTION_ORDER if x in merged]
        for section_key in merged:
            if section_key not in ordered_section_keys:
                ordered_section_keys.append(section_key)

        all_verified = True
        parts = []
        for section_key in ordered_section_keys:
            data = merged[section_key]
            if "_raw" in data:
                label = data.get("display_label", section_key)
                parts.append(f"### {label}\n\n{data['_raw']}")
                all_verified = False
            else:
                config_error = data.get("config_error")
                nv = data.get("not_verified", 0)
                fe = data.get("fetch_errors", 0)
                if config_error or nv > 0 or fe > 0:
                    all_verified = False
                parts.append(section_to_markdown(data))

        expected_count = len(SECTION_ORDER)
        if all_verified and len(ordered_section_keys) >= expected_count:
            content = (
                f"{timestamp}\n\n"
                "## Deployment verification on block explorers\n\n"
                "All deployment contracts are verified on block explorers."
            )
        else:
            content = (
                f"{timestamp}\n\n"
                "## Deployment verification on block explorers\n\n"
                + "\n".join(parts).rstrip()
            )

    body = (
        "<!-- UNVERIFIED_CONTRACTS_REPORT -->\n"
        f"{content}\n"
        "<!-- /UNVERIFIED_CONTRACTS_REPORT -->"
    )

    if args.output:
        Path(args.output).write_text(body, encoding="utf-8")
    else:
        print(body)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
