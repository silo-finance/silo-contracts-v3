#!/bin/bash
#
# Legacy Forge-based withdraw revenue runner.
# Delegates to run_withdraw_revenue.py (reads factories.json, stop-on-error, --from-id resume).
#
# Usage:
#   ./silo-core/scripts/withdrawFeesForge/withdrawRevenue.sh             # dry-run
#   ./silo-core/scripts/withdrawFeesForge/withdrawRevenue.sh --broadcast
#   ./silo-core/scripts/withdrawFeesForge/withdrawRevenue.sh 2>&1 | grep --line-buffered -iE 'WITHDRAWING|error|\[FAILED\]|\[OK\]|id='

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${SCRIPT_DIR}/run_withdraw_revenue.py" "$@"
