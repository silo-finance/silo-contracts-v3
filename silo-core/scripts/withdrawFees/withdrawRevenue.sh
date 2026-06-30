#!/bin/bash
#
# Top-level orchestrator for the withdrawFees pipeline.
# For every chain it runs: 1_collect_factories.py -> 2_discover_silos.py -> WithdrawFees.s.sol
#
# Usage:
#   silo-core/scripts/withdrawFees/withdrawRevenue.sh [--parallel] [--dry-run] [chain ...]
#
#   --parallel   run all chains concurrently (logs go to logs/<chain>.log)
#   --dry-run    run the Solidity stage without --broadcast (simulation only)
#   chain ...    optional list of chain aliases (default: all known chains)
#
# A failure on one chain never aborts the others; a summary is printed at the end.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
WITHDRAW_SCRIPT="silo-core/scripts/withdrawFees/WithdrawFees.s.sol"

py() { PYTHONPATH="${SCRIPT_DIR}" python3 "$@"; }

# chain metadata comes from _common.py (single source of truth)
chain_rpc_env() { py -c "import sys,_common;print(_common.get_chain(sys.argv[1]).rpc_env)" "$1"; }
rpc_url_for_env() { py -c "import sys,_common;print(_common.load_dotenv().get(sys.argv[1],''))" "$1"; }

PARALLEL=false
DRY_RUN=false
CHAINS=()

for arg in "$@"; do
    case "$arg" in
        --parallel) PARALLEL=true ;;
        --dry-run)  DRY_RUN=true ;;
        -h|--help)  sed -n '2,14p' "${BASH_SOURCE[0]}"; exit 0 ;;
        --*)        echo "Unknown flag: $arg" >&2; exit 1 ;;
        *)          CHAINS+=("$arg") ;;
    esac
done

if [ "${#CHAINS[@]}" -eq 0 ]; then
    mapfile -t CHAINS < <(py -c "import _common;print('\n'.join(_common.CHAINS))")
fi

run_chain() {
    local chain="$1"
    local env_var rpc broadcast

    env_var="$(chain_rpc_env "$chain")" || { echo "[$chain] unknown chain alias"; return 1; }
    rpc="$(rpc_url_for_env "$env_var")"
    if [ -z "$rpc" ]; then
        echo "[$chain] $env_var is empty/unset in .env, skipping"
        return 1
    fi

    echo "[$chain] stage 1/3: collect factories from git history"
    py "${SCRIPT_DIR}/1_collect_factories.py" --chain "$chain" || return 1

    echo "[$chain] stage 2/3: discover silos via RPC"
    py "${SCRIPT_DIR}/2_discover_silos.py" --chain "$chain" --rpc-url "$rpc" || return 1

    echo "[$chain] stage 3/3: withdraw fees"
    broadcast="--broadcast"
    $DRY_RUN && broadcast=""
    ( cd "$REPO_ROOT" && FOUNDRY_PROFILE=core forge script "$WITHDRAW_SCRIPT" --ffi --rpc-url "$rpc" $broadcast ) \
        || return 1
}

mkdir -p "$LOG_DIR"
declare -A STATUS

if $PARALLEL; then
    declare -A PIDS
    for chain in "${CHAINS[@]}"; do
        ( run_chain "$chain" ) >"${LOG_DIR}/${chain}.log" 2>&1 &
        PIDS[$chain]=$!
        echo "[$chain] started (pid ${PIDS[$chain]}) -> ${LOG_DIR}/${chain}.log"
    done
    for chain in "${CHAINS[@]}"; do
        if wait "${PIDS[$chain]}"; then STATUS[$chain]=OK; else STATUS[$chain]=FAIL; fi
    done
else
    for chain in "${CHAINS[@]}"; do
        echo "================ $chain ================"
        if run_chain "$chain" 2>&1 | tee "${LOG_DIR}/${chain}.log"; then
            STATUS[$chain]=OK
        else
            STATUS[$chain]=FAIL
        fi
    done
fi

echo ""
echo "==================== SUMMARY ===================="
overall=0
for chain in "${CHAINS[@]}"; do
    echo "  ${chain}: ${STATUS[$chain]:-SKIPPED}"
    [ "${STATUS[$chain]:-}" = "FAIL" ] && overall=1
done

echo ""
echo "Revenue lines (from logs):"
if ! grep -hE "daoAndDeployerRevenue in token" "${LOG_DIR}"/*.log 2>/dev/null | sed 's/^/  /'; then
    echo "  (none detected)"
fi
echo "================================================="

exit $overall
